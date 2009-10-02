use feature ':5.10';
use MooseX::Declare;

class Haver::Server::Env {
    our $VERSION = 0.01;
    our $AUTHORITY = 'cpan:DHARDISON';
    use Tie::CPHash;
    use Set::Object;

    use Haver::Server::Handle;
    use Haver::Server::List;
    use Haver::Server::Fail;

    has '_handles' => (
        traits  => ['NoGetopt'],
        is      => 'ro',
        isa     => 'Set::Object',
        default => sub { Set::Object->new },
        handles => {
            insert_handle => 'insert',
            remove_handle => 'remove',
        }
    );

    has '_user_map' => (
        traits    => [ 'NoGetopt', 'Hash'],
        is        => 'ro',
        isa       => 'HashRef[Haver::Server::Handle]',
        default   => sub { tie my %cphash, 'Tie::CPHash'; \%cphash },
        handles   => {
            set_user => 'set',
            get_user => 'get',
            has_user => 'exists',
            del_user => 'delete',
        },
    );

    has '_room_map' => (
        traits  => ['NoGetopt', 'Hash'],
        is      => 'ro',
        isa     => 'HashRef[Haver::Server::List]',
        default => sub { tie my %cphash, 'Tie::CPHash'; \%cphash },
        handles => {
            set_room => 'set',
            get_room => 'get',
            has_room => 'exists',
            del_room => 'delete',
            rooms    => 'keys',
        },
    );

    after remove_handle(Haver::Server::Handle $h) {
        # we don't call del_user() because of the next before statement.
        delete $self->_user_map->{ $h->name } if $h->has_name;
    }

    around set_user(Str $name, Haver::Server::Handle $handle) {
        return $self->$orig($name, $handle) unless $self->has_user($name);
        Haver::Server::Fail->throw( user_exists => $name );
    }

    around get_user(Str $name) {
        return $self->$orig($name) if $self->has_user($name);
        Haver::Server::Fail->throw( user_not_found => $name );
    }

    before del_user(Str $name) {
        my $user = $self->get_user($name);
        if (defined $user) {
            $self->_handles->remove( $user );
        }
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


}
