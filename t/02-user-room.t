#!/usr/bin/perl
use strict;
use warnings;
use Test::More tests => 8;
use Test::Exception;

use ok 'Haver::Server::User';
use ok 'Haver::Server::Room';

my $dylan = Haver::Server::User->new(name => 'dylan');
my $lobby = Haver::Server::Room->new(name => 'lobby');

$dylan->insert($lobby);

ok($lobby->contains($dylan));
ok($dylan->contains($lobby));

$lobby->remove($dylan);

ok(!$lobby->contains($dylan));
ok(!$dylan->contains($lobby));

dies_ok {
	$lobby->insert($lobby);
};

dies_ok {
	$dylan->insert($dylan);
};

