package DDG::Goodie::Teredo;
# ABSTRACT: Provides the Teredo server IPv4 address,
# NAT IPv4 address, and port number encoded in a given
# Teredo tunnel IPv6 address.

use strict;
use DDG::Goodie;
with 'DDG::GoodieRole::WhatIs';
use Net::IP;
use Math::BaseConvert;

triggers start => 'teredo';

zci answer_type => 'teredo';
zci is_cached   => 1;

my $matcher = wi_custom(
    groups => ['imperative', 'prefix'],
    options => {
        command => qr/teredo/i,
    },
);

handle query => sub {
    my $query = shift;
    my @output = ();
    my $match = $matcher->full_match($query) or return;

    # Create an IPv6 address from the query value
    my $ip = new Net::IP ($match->{value},6);

    # Verify the query value is a valid Teredo IPv6 address
    if ((defined $ip) && ($ip->version() == 6) && (substr($ip->ip(),0,9) eq "2001:0000")) {
	my $binip = $ip->binip();

	# bits 32 to 64 designate IPv4 address of the Teredo server used
	push @output, (new Net::IP (Net::IP::ip_bintoip((substr $binip, 32, 32),4)));

	# negation of bits 80 to 96, converted to decimal, designate NAT port number
	push @output, (65535 - cnv((substr $binip, 80, 16),2,10));

	# negation of bits 96 to 128 designate IPv4 address of NAT device
	push @output, (new Net::IP (Net::IP::ip_bintoip(~(substr $binip, 96, 32),4)));
	return answer => to_text(@output), html => to_html(@output);
    }
    return;

    # Params: server, port, client
    sub to_text {
	return "Teredo Server IPv4: " . $_[0]->ip() . "\nNAT Public IPv4: " . $_[2]->ip()
		. "\nClient Port: " . $_[1];
    }

    # Params: server, port, client
    sub to_html {
	return "<div><span class=\"teredo__label text--secondary\">Teredo Server IPv4: </span><span class=\"text--primary\">" . $_[0]->ip()
	. "</span></div><div><span class=\"teredo__label text--secondary\">NAT Public IPv4: </span><span class=\"text--primary\">" . $_[2]->ip()
	. "</span></div><div><span class=\"teredo__label text--secondary\">Client Port: </span><span class=\"text--primary\">" . $_[1] . "</span></div>";
    }
};

1;
