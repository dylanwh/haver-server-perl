package Haver::Protocol;
use strict;
use warnings;

our $VERSION = '0.01';
our $AUTHORITY = 'cpan:DHARDISON';

use Sub::Exporter -setup => {
	exports => [qw( haver_decode haver_encode )],
};

my %ESC   = ( "\r" => 'r', "\e" => 'e', "\n" => 'n', "\t" => 't' );
my %UNESC = map { ( $ESC{$_}, $_ ) } keys %ESC;

sub haver_decode {
	my ($line) = @_;
	return map { unescape($_) } split(/\t/, $line);
}

sub haver_encode {
	my (@msg) = @_;
	return join("\t", map { escape($_) } @msg);
}

sub unescape {
	my ($str) = @_;
	$str =~ s/\e([rent])/$UNESC{$1}/g;
	return $str;
}

sub escape {
	my ($str) = @_;
	$str =~ s/([\r\e\n\t])/\e$ESC{$1}/g;
	return $str;
}

1;
