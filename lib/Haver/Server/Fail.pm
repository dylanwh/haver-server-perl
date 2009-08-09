use MooseX::Declare;
use feature ':5.10';

class Haver::Server::Fail extends Haver::Server::Error {
    our $VERSION = '0.01';
    our $AUTHORITY = 'cpan:DHARDISON';

    has 'name' => (
        is       => 'ro',
        isa      => 'Str',
        required => 1,
    );

    has 'args' => (
        is         => 'ro',
        isa        => 'ArrayRef[Str]',
        default    => sub { [] },
        auto_deref => 1,
    );

    sub BUILDARGS {
        my ($class, $name, @args) = @_;
        return { name => $name, args => \@args };
    }
}
