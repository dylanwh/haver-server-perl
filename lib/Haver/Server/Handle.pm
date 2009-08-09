use MooseX::Declare;
use feature ':5.10';

use AnyEvent::Handle;

class Haver::Server::Handle
    is dirty
    extends AnyEvent::Handle 
    with MooseX::Param
{
    use MooseX::NonMoose;
    use Moose::Util::TypeConstraints;
    use Haver::Protocol 'haver_decode', 'haver_encode';
    clean;

    has 'name' => (
        is         => 'rw',
        isa        => 'Str',
        lazy_build => 1,
    );

    has 'phase' => (
        is      => 'rw',
        isa     => Moose::Util::TypeConstraints::enum [ 'new', 'login', 'normal' ],
        default => 'new',
    );

    has 'on_message' => (
        is       => 'ro',
        isa      => 'CodeRef',
        required => 1,
    );

    sub FOREIGNBUILDARGS {
        my $class = shift;
        return (
            @_, 
            on_read => $class->can('_on_read'),
        );
    }

    sub _build_name {
        my ($self) = @_;
        return "#" . filono($self->fh);
    }

    method _on_read() {
        $self->push_read(
            line => sub {
                my ($self, $line) = @_;
                $self->on_message->($self, haver_decode($line));
            }
        );
    }

    method send(Str $cmd, @args) {
        $self->push_write(haver_encode($cmd, @args) . "\r\n");
    }

}
