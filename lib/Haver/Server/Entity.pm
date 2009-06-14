use MooseX::Declare;
use MooseX::AttributeHelpers;

role Haver::Server::Entity is dirty {
	our $VERSION = '0.01';
	our $AUTHORITY = 'cpan:DHARDISON';

	use MooseX::Types::Moose qw( Object Str HashRef );
	clean;

    has 'house' => (
        isa       => 'Haver::Server::House',
        weak_ref  => 1,

        reader    => 'house',
        writer    => 'attach',
        clearer   => 'detach',
        predicate => 'is_attached',
    );

    has 'name' => (
        is       => 'ro',
        isa      => Str,
        required => 1,
    );

    has 'attr' => (
        metaclass => 'Collection::Hash',
        is        => 'ro',
        isa       => HashRef[Str],
        default   => sub { {} },
        provides  => {
            'set'    => 'set_attr',
            'get'    => 'get_attr',
            'delete' => 'del_attr',
            'exists' => 'has_attr',
        },
    );

    has '_set' => (
        is       => 'ro',
        isa      => 'Set::Object',
        default  => sub { 'Set::Object'->new },
        init_arg => undef,
        handles  => {
        	contents => 'members',
        	contains => 'contains',
        	_insert  => 'insert',
        	_remove  => 'remove',
        	_clear   => 'clear',
        },
    );

    requires 'insert';
    requires 'remove';

    before attach(Ref $house) { $self->_clear }
    before detach()           { $self->_clear }

}
