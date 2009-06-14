use MooseX::Declare;
use Set::Object::Weak;

class Haver::Server::Room
	is dirty
	with Haver::Server::Entity
{
	our $VERSION = '0.01';
	our $AUTHORITY = 'cpan:DHARDISON';

	use Haver::Server::Types 'User';
	clean;

    method insert(User $user) {
    	$self->_insert($user);
    	$user->_insert($self);
    }

    method remove(User $user) {
    	$self->_remove($user);
    	$user->_remove($self);
    }



}
