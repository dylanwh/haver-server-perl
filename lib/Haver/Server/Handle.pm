use MooseX::Declare;
use feature ':5.10';

use Haver::Server::Types;
use AnyEvent::Handle;
use Set::Object ();


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

    has 'on_message' => (
        is       => 'ro',
        isa      => 'CodeRef',
        required => 1,
    );

    has 'last_timeout' => (
        is => 'rw',
        predicate => 'has_last_timeout',
        clearer   => 'reset_last_timeout',
    );

    has 'phase' => (
        is => 'rw',
        isa => 'Str',
        default => 'new',
    );
    
    has '_lists' => (
        is       => 'ro',
        isa      => 'Set::Object',
        init_arg => undef,
        default  => sub { Set::Object::Weak->new },
        handles  => { lists => 'members' },
    );

    sub FOREIGNBUILDARGS {
        my $class = shift;
        return (
            @_, 
            on_read => $class->can('_on_read'),
        );
    }

    method _build_name() {
        return "#" . fileno($self->fh);
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

    # should only be called in Haver::Server::List
    method subscribe(Haver::Server::List $list) {
        $self->_lists->insert($list);
    }

    # should only be called in Haver::Server::List
    method unsubscribe(Haver::Server::List $list) {
        $self->_lists->remove($list);
    }
}
