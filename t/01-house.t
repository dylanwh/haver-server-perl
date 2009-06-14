#!/usr/bin/perl
use strict;
use warnings;
use Test::More tests => 17;
use Test::Exception;

use ok 'Haver::Server::House';

my $house = Haver::Server::House->new;

my $dylan = $house->new_user('dylan');
isa_ok($dylan, 'Haver::Server::User');

my $lobby = $house->new_room('lobby');
isa_ok($lobby, 'Haver::Server::Room');

ok($house->has_room('lobby'), "there is a lobby");
ok($house->has_user('dylan'), "three is a dylan");

$house->join_room('lobby', 'dylan');
ok($dylan->contains($lobby), "dylan is in lobby");
ok($lobby->contains($dylan), "lobby has dylan");

my $bd_ = $house->new_user('bd_');
$house->join_room('lobby', 'BD_');


my @users = sort ($bd_, $dylan);
my @users2 = sort $house->users;

is_deeply(\@users, \@users2, "userlist is sane");

$bd_ = undef;

ok($lobby->contains( $house->get_user('bd_') ), "bd_ is in lobby");


$house->delete_user('bd_');
dies_ok {
    $house->get_user('bd_');
} 'bd_ does not exist';

$house->delete_user('dylan');

ok(!$dylan->is_attached, "dylan is not attached to the house");
dies_ok {
    $house->get_user('dylan');
};
ok(!$lobby->contains( $dylan ), "dylan is not in lobby");
ok(!$dylan->contains($lobby), "dylan is consistent");

$house->add_user($dylan);
$house->join_room('lobby', 'dylan');

ok($dylan->contains($lobby), "dylan is back in lobby");
$house->delete_room('lobby');
ok(!$dylan->contains($lobby), "dylan is back out of lobby");

is($dylan, $house->get_user('DYLAN'), 'case insensitive');



