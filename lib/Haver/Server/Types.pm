package Haver::Server::Types;
use strict;
use warnings;

our $VERSION = '0.01';
our $AUTHORITY = 'cpan:DHARDISON';

use MooseX::Types::Moose qw( Object );
use MooseX::Types -declare => [qw[Entity User Room]];

subtype Entity, as Object, where { $_->does('Haver::Server::Entity') };
subtype User, as Object, where { $_->isa('Haver::Server::User') };
subtype Room, as Object, where { $_->isa('Haver::Server::Room') };


1;
