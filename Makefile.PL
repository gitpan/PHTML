#-*-perl-*-

use ExtUtils::MakeMaker;
WriteMakefile(NAME => 'HTML::PHTML',
	      VERSION_FROM => 'PHTML.pm',
              'dist' => {COMPRESS=>'gzip -9f', SUFFIX => 'gz'},
	      );
