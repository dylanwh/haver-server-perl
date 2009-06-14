use MooseX::Declare;
use Set::Object::Weak;

class Haver::Server::User
	is dirty
	with Haver::Server::Entity
{
	our $VERSION = '0.01';
	our $AUTHORITY = 'cpan:DHARDISON';

	use Haver::Server::Types 'Room';
	clean;

    method insert(Room $room) {
    	$self->_insert($room);
    	$room->_insert($self);
    }

    method remove(Room $room) {
    	$self->_remove($room);
    	$room->_remove($self);
    }


}
