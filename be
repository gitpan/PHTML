#!/usr/local/bin/perl -w

#use lib '/home/joshua/Maker-2.05';
use Config;
require Maker::Package;
require Maker::Rules;

my $pk = new Maker::Package(top=>'PHTML');
$pk->pm_2version('PHTML.pm');
$pk->default_targets('phtml');

my $inst = {
    man3 => [ 'Eval.3', 'PHTML.3' ],
    lib => ['HTML/', 'Experimental/',
	    'HTML/PHTML.pm', 'HTML/PHTML.html',
	    'Experimental/Eval.pm','Experimental/Eval.html'],
};

my $r = Maker::Rules->new($pk, 'perl-module');
$pk->a(new Maker::Seq($r->blib($inst), 
		      new Maker::Phase($r->pod2man('Eval.pm', 3),
				       $r->pod2man('PHTML.pm', 3),
				       $r->pod2html('Eval.pm', 'PHTML.pm')),
		      $r->populate_blib($inst),
		      new Maker::Unit('phtml', sub {}),
		      ),
       $r->test_harness,
       $r->install($inst),
       $r->uninstall($inst),
       );
$pk->load_argv_flags;
$pk->top_go(@ARGV);
