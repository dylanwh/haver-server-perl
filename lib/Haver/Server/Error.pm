use MooseX::Declare;
use feature ':5.10';

class Haver::Server::Error {
    our $VERSION = '0.01';
    our $AUTHORITY = 'cpan:DHARDISON';

    sub throw {
        my $class = shift;
        die $class->new(@_);
    }
}
