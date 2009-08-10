use MooseX::Declare;
use MooseX::AttributeHelpers;
use MooseX::Getopt; # for NoGetopt trait.
use feature ':5.10';

use Haver::Protocol  ();
use Haver::Server::Handle;
use Haver::Server::List;

use Haver::Server::Fail;
use Haver::Server::Bork;

use AnyEvent ();
use AnyEvent::Socket ();
use Tie::CPHash  ();
use Set::Object  ();
use Scalar::Util ();

class Haver::Server::Drop extends Haver::Server::Error;

class Haver::Server with MooseX::Runnable with MooseX::Getopt {
    use TryCatch;

    our $VERSION = '0.01';
    our $AUTHORITY = 'cpan:DHARDISON';

    has 'hostname'  => (is => 'ro', isa => 'Str',        required => 1    );
    has 'interface' => (is => 'ro', isa => 'Maybe[Str]', default  => undef);
    has 'port'      => (is => 'ro', isa => 'Int',        required => 1    );

    has 'version' => (
        traits  => ['NoGetopt'],
        is      => 'ro',
        isa     => 'Str',
        default => "Haver::Server/$VERSION",
    );

    has 'features' => (
        traits  => ['NoGetopt'],
        is      => 'ro',
        isa     => 'Str',
        default => 'auth,nick',
    );

    has 'current_handle' => (
        traits   => ['NoGetopt'],
        is       => 'rw',
        isa      => 'Haver::Server::Handle',
        weak_ref => 1,
        handles  => {
            reply         => 'send',
            param         => 'param',
            current_name  => 'name',
        },
    );

    has 'current_command' => ( traits => ['NoGetopt'], is => 'rw', isa => 'Str' );

    has 'handles' => (
        traits  => ['NoGetopt'],
        is      => 'ro',
        isa     => 'Set::Object',
        default => sub { Set::Object->new },
        handles => {
            'insert_handle' => 'insert',
            'remove_handle' => 'remove',
        }
    );

    has 'user_map' => (
        traits    => [ 'NoGetopt' ],
        is        => 'ro',
        isa       => 'HashRef[Haver::Server::Handle]',
        default   => sub { tie my %cphash, 'Tie::CPHash'; \%cphash },
        metaclass => 'Collection::Hash',
        provides  => {
            set    => 'set_user',
            get    => 'get_user',
            exists => 'has_user',
            delete => 'del_user',
        },
    );

    has 'room_map' => (
        traits   => ['NoGetopt'],
        is       => 'ro',
        isa      => 'HashRef[Haver::Server::List]',
        default  => sub { tie my %cphash, 'Tie::CPHash'; \%cphash },
        metaclass => 'Collection::Hash',
        provides => {
            set    => 'set_room',
            get    => 'get_room',
            exists => 'has_room',
            delete => 'del_room',
            keys   => 'rooms',
        },
    );

    method run() {
	    my $guard = AnyEvent::Socket::tcp_server($self->interface, $self->port, sub { $self->on_connect(@_) });

        my $iface = $self->interface || '*';
        my $port  = $self->port;
        say "Listening on $iface:$port";
	    AnyEvent->condvar->wait;

	    return 0;
    }

    # Callbacks
    method on_connect($fh, $host, $port) {
        say "New connection from $host:$port";

        my $handle = Haver::Server::Handle->new(
            fh       => $fh,
            linger   => 1,
            timeout  => 120,
            on_error => sub {
                my ( $handle, $fatal, $message ) = @_;
                warn $fatal ? "FATAL: " : "WARN: ", "$message";
                try { $self->quit( $handle, "error: $message" ) }
                catch { warn "error on_error: $@" }
            },
            on_eof => sub {
                my ( $handle ) = @_;
                say "Got EOF";
                try   { $self->quit( $handle, 'eof' ) }
                catch { warn "error from on_eof: $@" }
            },
            on_message => sub { 
                try   { $self->on_message(@_) }
                catch { warn "error from on_message: $@" }
            },
            on_timeout => sub {
                try { $self->on_timeout(@_) }
                catch { warn "error from on_timeout: $@" }
            },
        );

        $self->insert_handle($handle);
    }

    method on_message($handle, $name, @args) {
        my $method_name = "cmd_$name";
        $method_name =~ s/\W/_/g;
        say "Got command: $name";

        $self->current_handle($handle);
        $self->current_command($name);

        my $e;
        try {
            $self->validate_command();

            if ($self->can($method_name)) {
                my $method = $self->meta->get_method($method_name);
                my @params = eval { $method->_parsed_signature->positional_params() };
                my $required = grep { $_->required } @params;

                if (@args >= $required) {
                    $self->$method_name(@args);
                }
                else {
                    Haver::Server::Bork->throw(
                        "$name requires $required arguments."
                    );
                }
            }
            else {
                Haver::Server::Fail->throw('command-not-found');
            }
        }
        catch (Haver::Server::Fail $e) {
            my $name = $e->name;
            $name =~ s/_/-/g;
            $self->reply(FAIL => $self->current_command, $name, $e->args);
        }
        catch (Haver::Server::Bork $e) {
            $self->reply(BORK => $self->current_command, $e->message);
        }
        catch (Haver::Server::Drop $e) {
            warn "Dropping connection without notifcation";
            $self->cleanup($handle);
        }
        catch ($e) {
            $self->reply(BUG => $self->current_command, $e);
            warn "ERROR: $e";
        }
    }

    method on_timeout($handle) {
        if ($handle->has_last_timeout) {
            $self->quit($handle, 'timeout');
        }
        else {
            my $now = time;
            $handle->last_timeout($now);
            $handle->send(POKE => $now);
        }
    }

    # Utility methods
    method cleanup($handle) {
        foreach my $list ($handle->lists) {
            $list->remove($handle);
        }
        $self->remove_handle($handle);
        $self->del_user($handle->name) if $self->has_user($handle->name);
    }

    method quit($handle, $reason) {
        my $targets = $handle->observers;
        
        $targets->remove($handle);
        foreach my $target ($targets->members) {
            $target->send(QUIT => $handle->name, $reason);
        }
        $self->cleanup($handle);
    }

    method validate_command() {
        my $phase = $self->current_handle->phase;
        my $name  = $self->current_command;

        if ($phase eq 'new') {
            Haver::Server::Drop->throw if $name ne 'HAVER';
        }
        elsif ($phase eq 'ident') {
            Haver::Server::Bork->throw("Expected IDENT, got $name") if $name ne 'IDENT';
        }
        elsif ($phase eq 'interactive') {
            if ( $name eq 'IDENT' or $name eq 'HAVER' ) {
                Haver::Server::Bork->throw('Now is not the time for that.');
            }
        }
        else {
            die "Invalid phase";
        }
    }

    method get_info(MooseX::Param $thing) {
        my @info;
        for my $key (sort $thing->param) {
            my $val = $thing->param($key);
            next if ref $val;
            push @info, "$key=$val";
        }
        return @info;
    }

    around set_user(Str $name, Haver::Server::Handle $handle) {
        return $self->$orig($name, $handle) unless $self->has_user($name);
        Haver::Server::Fail->throw( user_exists => $name );
    }

    around get_user(Str $name) {
        return $self->$orig($name) if $self->has_user($name);
        Haver::Server::Fail->throw( user_not_found => $name );
    }

    around del_user(Str $name) {
        return $self->$orig($name) if $self->has_user($name);
        Haver::Server::Fail->throw( user_not_found => $name );
    }

    around set_room(Str $name, $set) {
        return $self->$orig($name, $set) unless $self->has_room($name);
        Haver::Server::Fail->throw( room_exists => $name );
    }

    around get_room(Str $name) {
        return $self->$orig($name) if $self->has_room($name);
        linger => 1,
        Haver::Server::Fail->throw( room_not_found => $name );
    }

    around del_room(Str $name) {
        return $self->$orig($name) if $self->has_room($name);
        Haver::Server::Fail->throw( room_not_found => $name );
    }

    # Protocol handlers.
    method cmd_HAVER($version, $features? = "") {
        my $handle = $self->current_handle;
        $handle->param( version => $version );
        $handle->send(
            HAVER => (
                $self->hostname, 
                $self->version, 
                $self->features,
            )
        );
        $handle->phase('ident');
        $handle->parse_features($features);
    }

    method cmd_IDENT($name) {
        my $handle = $self->current_handle;
        $self->set_user($name => $handle);
        $handle->name($name);
        $handle->send(HELLO => $name);
        $handle->phase('interactive');
    }

    method cmd_TO($name, $type, @msg) {
        # a Haver::Server::Handle
        my $user = $self->get_user($name);
        $user->send(FROM => $self->current_name, $type, @msg);
    }

    method cmd_IN($name, $type, @msg) {
        my $room   = $self->get_room($name);
        my $sender = $self->current_handle;

        if (not $room->contains($sender)) {
            Haver::Server::Fail->throw(access_denied => $name);
        }

        foreach my $target ($room->members) {
            $target->send(IN => $name, $sender->name, $type, @msg);
        }
    } 

    method cmd_JOIN($name) {
        my $room   = $self->get_room($name);
        my $sender = $self->current_handle;

        if ($room->contains($sender)) {
            Haver::Server::Fail->throw('already_joined' => $name);
        }

        $room->insert($sender);
        foreach my $target ($room->members) {
            $target->send(JOIN => $name, $sender->name);
        }
    }

    method cmd_PART($name) {
        my $room   = $self->get_room($name);
        my $sender = $self->current_handle;

        if (not $room->contains($sender)) {
            Haver::Server::Fail->throw(already_parted => $name);
        }

        foreach my $target ($room->members) {
            $target->send(PART => $name, $sender->name);
        }
        $room->remove($sender);
    }

    method cmd_OPEN($name) {
        my $room = Haver::Server::List->new(
            name => $name
        );
        $room->param(owner => $self->current_name);

        $self->set_room($name => $room);
        $self->reply(OPEN => $name);
    }

    method cmd_CLOSE($name) {
        my $room = $self->get_room($name);
        my $sender = $self->current_handle;

        foreach my $target ($room->members) {
            $target->send(PART => $name, $target->name, 'closed', $sender->name);
        }
        $sender->send(CLOSE => $name);
        $self->del_room($name);
    }

    method cmd_LIST($name) {
        my $room   = $self->get_room($name);
        my $sender = $self->current_handle;

        if (not $room->contains($sender)) {
            Haver::Server::Fail->throw(
                access_denied => $name
            );
        }

        my @users = map { $_->name } $room->members;
        $self->reply(LIST => $name, @users);
    }

    method cmd_ROOMLIST() {
        $self->reply(ROOMLIST => $self->rooms);
    }

    method cmd_BYE($reason? = '') {
        $self->quit($self->current_handle, "bye: $reason");
        $self->reply(BYE => "bye: $reason");
    }

    method cmd_POKE($word) {
        $self->reply(OUCH => $word);
    }

    method cmd_OUCH($time) {
        my $handle = $self->current_handle;
        if (not $handle->has_last_timeout) {
            Haver::Server::Bork->throw(
                "OUCH without POKE"
            );
        }

        if ($handle->last_timeout eq $time) {
            $handle->reset_last_timeout();
        }
        else {
            $self->quit($handle, 'stale timeout');
        }
    }

    method cmd_NICK($nick) {
        my $handle = $self->current_handle;
        $handle->param(nick => $nick);
        $handle->broadcast(
            NICK => $handle->name, $nick
        );
    }

    method cmd_USERINFO($name) {
        my $user = $self->get_user($name);
        $self->reply(USERINFO => $name, $self->get_info($user));
    }

    method cmd_ROOMINFO($name) {
        my $room = $self->get_room($name);
        $self->reply(ROOMINFO => $name, $self->get_info($room));
    }

}
