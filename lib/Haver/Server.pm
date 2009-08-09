use MooseX::Declare;
use MooseX::AttributeHelpers;
use MooseX::Getopt; # for NoGetopt trait.
use feature ':5.10';

use Haver::Protocol  ();
use Haver::Server::Handle;

use AnyEvent::Socket ();
use Tie::CPHash      ();
use Set::Object      ();
use Scalar::Util     ();

class Haver::Server 
    with MooseX::Runnable
    with MooseX::Getopt
{
    our $VERSION = '0.01';
    our $AUTHORITY = 'cpan:DHARDISON';

    use TryCatch;

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
            given ($handle->phase) {
                when ('new') {
                    $self->cleanup($handle) if $name ne 'HAVER';
                }
                when ('login') {
                    if ($name ne 'IDENT') {
                        $self->bork("expected IDENT");
                    }
                }
                when ('normal') {
                    if ($name ~~ ['HAVER', 'IDENT']) {
                        $self->bork("$name only valid during new or login phase.");
                    }
                }
            }

            if ($self->can($method_name)) {
                my $method = $self->meta->get_method($method_name);
                my @params = $method->_parsed_signature->positional_params();
                my $required = grep { $_->required } @params;

                if ($required == @args) {
                    $self->$method_name(@args);
                }
                else {
                    $self->bork("$name requires $required arguments.");
                }
            }
            else {
                $self->fail('command-not-found');
            }
        }
        catch ($e) {
            $self->reply(BUG => $self->current_command, $e);
            warn "ERROR: $e";
        }
    }

    method bork($msg) {
        $self->reply(BORK => $msg);
        $self->cleanup($self->current_handle);
    }

    method fail($name, @msg) {
        $name =~ s/_/-/g;

        $self->reply(FAIL => $self->current_command, $name, @msg);
    }

    method cleanup($handle) {
        $self->remove_handle($handle);
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
        if ($self->has_user($name)) {
            $self->fail(user_exists => $name);
            return;
        }

        $self->current_name($name);
        $self->set_user($name => $self->current_handle);
        $self->reply(HELLO => $name);
    }

    method cmd_TO($name, $type, @msg) {
        if (not $self->has_user($name)) {
            $self->fail(user_not_found => $name);
            return;
        }

        # a Haver::Server::Handle
        my $user = $self->get_user($name);
        $user->send(FROM => $self->current_name, $type, @msg);
    }

}
