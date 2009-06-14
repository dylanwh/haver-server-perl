use MooseX::Declare;
use MooseX::AttributeHelpers;

use Haver::Server::User;
use Haver::Server::Room;
use Tie::CPHash ();

class Haver::Server::House {
	our $VERSION   = '0.01';
	our $AUTHORITY = 'cpan:DHARDISON';

    foreach my $n (qw( user room )) {
        has "_${n}s" => (
            metaclass => 'Collection::Hash',
            isa       => "HashRef[Haver::Server::\u$n]",
            init_arg  => undef,
            default   => sub { tie my %h, 'Tie::CPHash'; \%h },
            provides  => {
                'get'    => "get_$n",
                'exists' => "has_$n",
                'delete' => "delete_$n",
                'set'    => "_set_$n",
                'values' => "${n}s",
            },
        );
    }

	method new_user(Str $name) {
        $self->_set_user(
            $name => Haver::Server::User->new(
                house => $self,
                name  => $name,
            )
        );
	}

	method new_room(Str $name) {
		my $room = Haver::Server::Room->new(
			house => $self,
			name => $name,
		);
		$self->_set_room($name, $room);

		return $room;
	}

	method add_user(Haver::Server::User $user) {
		$self->_set_user($user->name, $user);
		$user->attach($self);
	}

	method add_room(Haver::Server::Room $room) {
		$self->_set_room($room->name, $room);
		$room->attach($self);
	}

	method join_room(Str $roomname, Str $username) {
		my $room = $self->get_room($roomname);
		my $user = $self->get_user($username);
		$user->insert($room);
	}

	method part_room(Str $roomname, Str $username) {
		my $room = $self->get_room($roomname);
		my $user = $self->get_user($username);
		$user->remove($room);
	}

	before delete_user(Str $name) {
		if ($self->has_user($name)) {
			my $user = $self->get_user($name);
			foreach my $room ($user->contents) {
				$room->remove( $user );
			}
			$user->detach;
		}
	}

	before delete_room(Str $name) {
		if ($self->has_room($name)) {
			my $room = $self->get_room($name);
			foreach my $user ($room->contents) {
				$user->remove( $room );
			}
			$room->detach;
		}
	}
}
