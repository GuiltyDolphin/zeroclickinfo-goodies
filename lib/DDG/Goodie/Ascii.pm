package DDG::Goodie::Ascii;
# ABSTRACT: ASCII

use strict;
use DDG::Goodie;
with 'DDG::GoodieRole::WhatIs';

triggers end => "ascii";

zci answer_type => "ascii_conversion";
zci is_cached   => 1;

my $matcher = wi_translation({
    groups => ['conversion'],
    options => {
        primary => qr/([01]{8})*/,
        to    => 'ascii',
    },
});

handle query_raw => sub {
    my $query = $_;
    my $result = $matcher->match($query);
    my $binary = $result->{value};
    my $ascii = pack("B*", $binary);

    return unless $ascii;

    return "$binary in binary is \"$ascii\" in ASCII",
      structured_answer => {
        input     => [$binary],
        operation => 'Binary to ASCII',
        result    => html_enc($ascii),
      };
};

1;

