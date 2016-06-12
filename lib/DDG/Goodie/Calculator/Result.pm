package DDG::Goodie::Calculator::Result;
# Defines the result form used by the Calculator Goodie to
# allow for more detailed and curated results.

BEGIN {
    require Exporter;

    our @ISA    = qw(Exporter);
    our @EXPORT = qw(new_result foreign
                     wrap_exact wrap_approx
                     produces_angle);
}

use Math::BigRat try => 'GMP';
use Math::Cephes qw(:explog);
use Math::Cephes qw(:trigs);
use Math::Round;
use Moose;
use Moose::Util::TypeConstraints;
use utf8;
use strict;
use warnings;
use List::Util qw(any max);

use overload
    '""'    => 'to_string',
    # Basic arithmetic
    '+'     => 'add_results',
    '-'     => 'subtract_results',
    '*'     => 'multiply_results',
    '/'     => 'divide_results',
    '%'     => 'modulo_results',
    '**'    => 'exponent_results',
    # Comparisons
    '<=>'   => 'num_compare_results',
    # Trig
    'atan2' => 'atan2_results',
    # Misc functions
    'exp'   => 'exp_result',
    'log'   => 'log_result',
    'sqrt'  => 'sqrt_result',
    'int'   => 'int_result';

class_type 'BigRat'   => { class => 'Math::BigRat' };
class_type 'BigInt'   => { class => 'Math::BigInt' };
class_type 'BigFloat' => { class => 'Math::BigFloat' };
union 'NumberThing'   => [qw(BigRat BigInt BigFloat)];

# The wrapped value.
has 'value' => (
    is       => 'rw',
    isa      => 'NumberThing',
    required => 1,
);

subtype 'DDG::Goodie::Calculator::Angle',
    as 'Str',
    where { $_ =~ /^radian|degree$/ };

has 'angle_type' => (
    is      => 'ro',
    isa     => 'Maybe[DDG::Goodie::Calculator::Angle]',
    default => undef,
);

# Will want a more robust solution than this. Allows checking if user
# specified /explicitly/ that an angle was in radians.
has 'declared' => (
    is      => 'ro',
    isa     => 'ArrayRef[Str]',
    default => sub { [] },
);

has precision => (
    is  => 'ro',
    isa => 'Int',
    default => -39,
);

sub is_degrees {
    my $self = shift;
    ($self->angle_type // '') eq 'degree'
};

sub is_radians {
    my $self = shift;
    ($self->angle_type // '') eq 'radian'
};

sub exact {
    my $num = shift;
    if ($num =~ /\.|e-|\//) {
        return Math::BigRat->new($num);
    } else {
        return Math::BigInt->new($num);
    }
}

sub wrap_exact {
    return new_result(value => exact(@_));
}

sub approx {
    my $num = shift;
    return Math::BigFloat->new($num);
}

sub wrap_approx {
    return new_result(value => approx(@_));
}

sub new_result { DDG::Goodie::Calculator::Result->new(@_) };

sub to_opts {
    my $self = shift;
    return (
        precision => $self->precision,
    );
}

# Ensure result is wrapped in a Calc::Result
sub with_wrap {
    my ($sub, %options) = @_;
    return sub {
        my $result = $sub->(@_);
        return new_result($_[0]->to_opts, %options, value => $result);
    };
}

sub produces_angle {
    my $sub = shift;
    return sub {
        my $result = $sub->(@_);
        my $copy = $result->declare('angle');
        return $copy;
    };
}

sub to_string {
    my $self = shift;
    my $res = $self->value();
    return "$res" if defined $res;
}

# Tell the Calculator that the value is an angle in degrees.
sub make_degrees {
    my $self = shift;
    my $copy = $self->copy;
    $copy->{angle_type} = 'degree';
    return $copy;
}

sub make_angle {
    my ($self, $angle) = @_;
    my $copy = $self->copy;
    $copy->{angle_type} = $angle;
    return ($copy->declare('angle'))->declare($angle);
}

sub make_radians {
    my $self = shift;
    $self->make_angle('radian');
}
sub copy {
    my $self = shift;
    return new_result {
        value      => $self->value,
        angle_type => $self->angle_type,
        declared   => $self->declared,
        precision  => $self->precision,
    };
}

# Make both results the same type, favoring Float then Rat
# then Int.
sub to_same_numt {
    my ($fst, $snd) = @_;
    my @refs = (ref $fst, ref $snd);
    return (floatify($fst), floatify($snd))
        if grep { $_ eq 'Math::BigFloat' } @refs;
    return (rattify($fst), rattify($snd))
        if grep { $_ eq 'Math::BigRat' } @refs;
    return ($fst, $snd);
}

sub fast_normalize {
    my $num = shift;
    return $num if is_int($num);
    return $num if is_frac($num);
    my $rounded = $num->copy->bfround(-30);
    if ($rounded->exponent > -20) {
        return exact($rounded);
    }
    return $num;
}

# Combine two Results using the given operation. Preserves appropriate
# attributes.
sub combine_results {
    my $sub = shift;
    return sub {
        my ($self, $other) = @_;
        my $angle = $self->angle_type;
        return unless ($self->angle_type // '') eq ($other->angle_type // '');
        my ($lhs, $rhs) = to_same_numt($self->value(), $other->value());
        my $declared = $self->declared // $other->declared;
        my $res = fast_normalize $sub->($lhs, $rhs);
        my $precision = max ($self->precision, $other->precision);
        return new_result {
            value      => $res,
            angle_type => $angle,
            declared   => $declared,
            precision  => $precision,
        };
    };
}

# fast_normalize with full access to Result attributes.
sub fnorm {
    my ($self, $num) = @_;
    return $num if is_float($num) && length $num->mantissa <= abs($self->precision);
    return fast_normalize($num);
}

sub upon_result {
    my ($sub, %options) = @_;
    return with_wrap sub {
        my $self = shift;
        return fnorm($self, ($sub->($self->value)));
    }, %options;
}

sub on_result { (upon_result($_[1]))->($_[0]) };

sub foreign {
    my ($sub, %options) = @_;
    my $wrapped = sub {
        Math::BigFloat->new($sub->(@_));
    };
    return upon_result($wrapped, %options);
}

*on_decimal = with_wrap sub {
    my ($self, $sub) = @_;
    my $res = $sub->($self->as_decimal());
    return $res;
};

*add_results = combine_results(sub { $_[0] + $_[1] });
*subtract_results = combine_results(sub { $_[0] - $_[1] });
*multiply_results = combine_results(sub { $_[0] * $_[1] });
*divide_results = combine_results(sub {
    my ($lhs, $rhs) = to_same_numt($_[0], $_[1]);
    return rattify("$_[0]/$_[1]") if is_int($lhs);
    return $_[0] / $_[1];
});
*modulo_results = combine_results(sub { $_[0] % $_[1] });

sub num_compare_results {
    my ($self, $other) = @_;
    return $self->value()  <=> $other->value();
}

sub from_big {
    my $to_convert = shift;
    return $to_convert->numify() if ref $to_convert eq 'Math::BigRat';
    return $to_convert->bstr() if ref $to_convert eq 'Math::BigFloat';
    return $to_convert;
}

sub to_rat {
    my $num = shift;
    return $num if ref $num eq 'Math::BigRat';
    return Math::BigRat->new($num);
}

# Unwrap the arguments from Big{Float,Rat} for operations such as sine
# and log.
sub with_unwrap {
    my $sub = shift;
    return sub {
        my @args = @_;
        return $sub->(map { from_big($_) } @args);
    };
}

sub wrap_unwrap {
    my $sub = shift;
    return sub {
        return to_rat(with_unwrap($sub)->(@_));
    };
}

# ~~Little bit hacky for exponents because of the way Number::Fraction
# handles them. Basically have to deal with the case when the base and
# exponent are valid fractions, and the exponent is negative - other cases
# are handled fine by Number::Fraction.~~
#
# Issues with GMP and highly-precise fractions; this works
# around that but does mean certain queries are not as
# informative (though not incorrect).
#
# TODO: Make this work *fully* with *all* inputs.
sub exponentiate_fraction {
    return Math::BigRat->new(
        Math::BigFloat->new($_[0])->numify
        ** Math::BigFloat->new($_[1])->numify
    );
}

# Hardcoded for precision
our $euler = Math::BigFloat->new(
    '2.7182818284590452353602874713526624977572470936999' .
    '595749669676277240766303535476'
);
my $e = $euler;

*exponent_results = combine_results \&exponentiate_fraction;
*atan2_results = combine_results \&atan2;
*exp_result = upon_result sub { $e ** $_[0] };
*log_result = upon_result sub { floatify($_[0])->blog };
*sqrt_result = upon_result sub { sqrt floatify($_[0]) };
*int_result = upon_result sub { int $_[0] };

# logY(X)
*logbase = combine_results sub { floatify($_[0])->blog($_[1]) };

# Bounded (absolute) input size.
sub bounded {
    my ($bound, $sub) = @_;
    return sub {
        return if any { abs $_ > $bound } @_;
        return $sub->(@_);
    };
}

*sinh = upon_result bounded 1000 => sub {
    my $val = shift;
    return (($e ** $val) - ($e ** (-$val))) / 2
};
*cosh = upon_result bounded 1000 => sub {
    my $val = shift;
    return (($e ** $val) + ($e ** (-$val))) / 2
};
*tanh = upon_result bounded 1000 => sub {
    my $val = shift;
    return (($e ** $val) - ($e ** (-$val))) /
            (($e ** $val) + ($e ** (-$val)))
};

sub is_float {
    my $self = shift;
    return ref $self->value eq 'Math::BigFloat';
}
*asinh = upon_result sub {
    log (floatify($_[0]) + sqrt(floatify($_[0]) ** 2 + 1));
};
*acosh = upon_result sub {
    log (floatify($_[0]) + sqrt(floatify($_[0]) ** 2 - 1));
};
*atanh = upon_result sub {
    (1/2) * log((1 + $_[0]) / (1 - $_[0]));
};

sub as_float {
    my $self = shift;
    if ($self->is_fraction) {
        return $self->value->as_float();
    } elsif ($self->is_float) {
        return $self->value->copy();
    } else {
        return Math::BigFloat->new($self->value);
    }
}

my $PI = Math::BigFloat->bpi();
sub deg2rad {
    my $to_convert = shift;
    return ($PI * $to_convert) / 180;
}

sub rad2deg {
    my $to_convert = shift;
    return (180 * $to_convert) / $PI;
}

sub to_radians {
    my $self = shift;
    if ($self->is_degrees) {
        my $res = $self->on_result(\&deg2rad);
        return $res->make_radians();
    };
    $self->make_radians();
};

sub to_degrees {
    my $self = shift;
    my $is_radians = $self->is_radians();
    return $self if $self->is_degrees();
    if ($self->is_radians || $self->declares('angle')) {
        my $res = $self->on_result(\&rad2deg);
        return $res->make_degrees();
    };
    $self->make_degrees();
};

sub with_radians {
    my $sub = shift;
    return sub {
        my $self = shift;
        my $rads = $self->to_radians();
        return $rads->on_result($sub);
    };
}

*rsin = with_radians(sub {
    my $princ = floatify($_[0]) % (2*$PI);
    $princ->bsin();
});
*rcos = with_radians(sub {
    my $princ = floatify($_[0]) % (2*$PI);
    $princ->bcos();
});

sub as_fraction_string {
    my $self = shift;
    my $value = $self->value();
    return "$value";
}

sub is_integer {
    my $self = shift;
    my $value = $self->value();
    return $value->is_int() if ref $value eq 'Math::BigRat';
    return $value =~ /^\d+$/;
}

sub is_fraction {
    my $self = shift;
    return ref $self->value() eq 'Math::BigRat';
}

sub as_rounded_decimal {
    my $self = shift;
    my $decimal = $self->value();
    my ($nom, $expt) = split 'e', $decimal;
    my ($s, $e) = split 'e', sprintf('%0.13e', $decimal);
    return nearest(1e-12, $s) * 10 ** $e;
}

sub rounded_float {
    my ($self, $round_to) = @_;
    return $self->as_float->bround($round_to);
}

sub angle_symbol {
    my $self = shift;
    if ($self->is_degrees) {
        return '°';
    } elsif ($self->is_radians) {
        return ' ㎭' if $self->declares('radian');
    };
    return '';
}

sub declare {
    my ($self, $to_declare) = @_;
    my $copy = $self->copy();
    my @declared = (@{$copy->{declared}}, $to_declare);
    $copy->{declared} = \@declared;
    return $copy;
}
sub declares {
    my ($self, $to_check) = @_;
    return any { $_ eq $to_check } @{$self->declared};
}

sub as_decimal {
    my $self = shift;
    my $value = $self->value();
    return $value->as_float->bstr() if ref $value eq 'Math::BigRat';
    return $value->bstr() if ref $value eq 'Math::BigFloat';
    return $value->bstr() if ref $value eq 'Math::BigInt';
    return $value;
}

*rounded = with_wrap sub {
    my ($self, $round_to) = @_;
    return to_rat("@{[nearest($round_to, $self->as_decimal())]}");
};

sub contains_bad_result {
    my $self = shift;
    return $self->value() =~ /(inf|nan)/i;
}

__PACKAGE__->meta->make_immutable;

1;
