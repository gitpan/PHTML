# -*-perl-*-

sub ok { print "ok $tx\n"; $tx++; }
sub not_ok { print "not ok $tx\n"; $tx++; }

BEGIN { $| = 1; $tx=1; print "1..3\n"; }
END {not_ok unless $loaded;}

use strict;
use integer;
use vars qw($B $cmd $ph $loaded);
use FindBin;
use IO::File;
require HTML::PHTML;

$loaded = 1;
ok; #1

sub small_caps { lc shift; }
sub extern_href {
    my ($label, $href) = @_;
    '<a href="'.$href.'">'.$label."</a>";
}
sub is_cmd { my $yes = $cmd eq shift; $cmd=''; $yes }

$cmd = '';
chdir $FindBin::Bin or die "chdir $FindBin::Bin: $!";
$ph = new HTML::PHTML($FindBin::Bin, 0);
#$ph->debug(1);

sub go {
    $B='';
    $ph->x("demo");
    my $fh = new IO::File;
    $fh->open(">out.html") or die "open >out.html: $!";
    print $fh $B;
}

sub check {
    # also see Test::Output (via CPAN)
    my ($new,$old) = @_;
    if (-e $old) {
	system("diff $old $new")==0? ok:not_ok;
	unlink $new;
    } else {
	system("mv $new $old")==0? ok:not_ok;
    }
}

go();
check("out.html", "b1.good"); #2

$cmd = 'login'; 
go();
check("out.html", "b2.good"); #3


