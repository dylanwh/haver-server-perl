use MooseX::Declare;
use Set::Object ();

use Haver::Server::Types;

class Haver::Server::List with MooseX::Param {
    our $VERSION = '0.01';
    our $AUTHORITY = 'cpan:DHARDISON';

    has 'name' => (
        is       => 'ro',
        isa      => 'Str',
        required => 1,
    );

    has '_users' => (
        is       => 'ro',
        isa      => 'Set::Object',
        init_arg => undef,
        default  => sub { Set::Object->new },
        handles => [ qw( members )],
    );

    method insert(Haver::Server::Handle $handle) {
        $handle->subscribe($self);
        $self->_users->insert($handle);
    }

    method remove(Haver::Server::Handle $handle) {
        $handle->unsubscribe($self);
        $self->_users->remove($handle);
    }

    method contains(Haver::Server::Handle $handle) {
        $self->_users->contains($handle);
    }

}
