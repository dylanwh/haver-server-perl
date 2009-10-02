use feature ':5.10';
use MooseX::Declare;

role Haver::Server::Role::HasEnv {
    our $VERSION = 0.01;
    our $AUTHORITY = 'cpan:DHARDISON';

    use Haver::Server::Env;

    has 'env' => (
        traits     => ['NoGetopt'],
        is         => 'ro',
        isa        => 'Haver::Server::Env',
        lazy_build => 1,
        handles    => [
            qw[
                set_room
                get_room
                has_room
                del_room
                rooms

                set_user
                get_user
                has_user
                del_user

                insert_handle
                remove_handle
            ]
        ]
    );

    method _build_env() { Haver::Server::Env->new }
}
