use MooseX::Declare;
use feature ':5.10';

class Haver::Server::Bork extends Haver::Server::Error {
    our $VERSION = '0.01';
    our $AUTHORITY = 'cpan:DHARDISON';

    has 'message' => (
        is       => 'ro',
        isa      => 'Str',
        required => 1,
    );

    sub BUILDARGS {
        my ($class, $message) = @_;
        return { message => $message };
    }
}
