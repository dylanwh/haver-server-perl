use MooseX::Declare;
use MooseX::AttributeHelpers;
use MooseX::Getopt; # for NoGetopt trait.
use feature ':5.10';

use Haver::Protocol  ();
use Haver::Server::Handle;
use Haver::Server::Fail;
use Haver::Server::Bork;

use AnyEvent ();
use AnyEvent::Socket ();
use Tie::CPHash  ();
use Set::Object  ();
use Scalar::Util ();


class Haver::Server with MooseX::Runnable with MooseX::Getopt {
    use TryCatch;

    our $VERSION = '0.01';
    our $AUTHORITY = 'cpan:DHARDISON';

    has 'hostname'  => (is => 'ro', isa => 'Str',        required => 1    );
    has 'interface' => (is => 'ro', isa => 'Maybe[Str]', default  => undef);
    has 'port'      => (is => 'ro', isa => 'Int',        required => 1    );

    has 'current_handle' => (
        traits  => ['NoGetopt'],
        is      => 'rw',
        isa     => 'Haver::Server::Handle',
        handles => {
            reply        => 'send',
            param        => 'param',
            current_name => 'name',
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

    has 'usermap' => (
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

    has 'roommap' => (
        traits   => ['NoGetopt'],
        is       => 'ro',
        isa      => 'HashRef[Set::Object]',
        default  => sub { tie my %cphash, 'Tie::CPHash'; $cphash{main} = Set::Object::Weak->new;  \%cphash },
        metaclass => 'Collection::Hash',
        provides => {
            set    => 'set_room',
            get    => 'get_room',
            exists => 'has_room',
            delete => 'del_room',
            keys   => 'rooms',
        },
    );

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
        Haver::Server::Fail->throw( room_not_found => $name );
    }

    around del_room(Str $name) {
        return $self->$orig($name) if $self->has_room($name);
        Haver::Server::Fail->throw( room_not_found => $name );
    }


    method run() {
	    my $guard = AnyEvent::Socket::tcp_server($self->interface, $self->port, sub { $self->on_connect(@_) });

        my $iface = $self->interface || '*';
        my $port  = $self->port;
        say "Listening on $iface:$port";
	    AnyEvent->condvar->wait;

	    return 0;
    }

    method on_connect($fh, $host, $port) {
        say "New connection from $host:$port";

        my $handle = Haver::Server::Handle->new(
            fh => $fh,
            on_error => sub {
                my ($handle, $fatal, $message) = @_;
                warn  $fatal ? "FATAL: " : "WARN: ", "$message";
                $self->cleanup($handle);
            },
            on_eof     => sub { say "Got EOF"; $self->cleanup($_[0]) },
            on_message => sub { $self->on_message(@_) },
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
            if ($self->can($method_name)) {
                my $method = $self->meta->get_method($method_name);
                my @params = eval { $method->_parsed_signature->positional_params() };
                my $required = grep { $_->required } @params;

                if ($required == @args) {
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
        catch (Item $e) {
            $self->reply(BUG => $self->current_command, $e);
            warn "ERROR: $e";
        }
    }

    method cleanup($handle) {
        $self->remove_handle($handle);
        try { $self->del_user($handle->name) }
        $handle->destroy;
    }

    method cmd_HAVER($useragent, $extensions? = "") {
        $self->param(
            useragent  => $useragent,
            extensions => [split(/,/, $extensions)],
        );
        $self->reply(HAVER => $self->hostname, "Haver::Server $VERSION");
    }

    method cmd_IDENT($name) {
        $self->set_user($name => $self->current_handle);
        $self->current_name($name);
        $self->reply(HELLO => $name);
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
}
