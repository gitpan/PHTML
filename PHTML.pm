package HTML::PHTML::Page;
use strict;
use integer;
use Carp;
use IO::File;
use File::stat;
require Experimental::Eval;

sub new {
    my ($class, $pkg, $src) = @_;
    bless { pkg => $pkg, src => $src }, $class;
}

sub reload {
    my ($pg, $debug) = @_;
    my $st = stat($pg->{src});
    return if (!$debug and
	       $pg->ok and
	       $st and
	       $pg->{mtime} >= $st->mtime);

    my $fh = new IO::File;
    $fh->open($pg->{src}) or die "open $pg->{src}: $!";
    my $C = "package $pg->{pkg}; sub {\n";
    my $line = 0;
    my $prefix = '$B.=';
    my $reply = 'sub {0}';
    my $reply_line = 0;
    while (1) {
	my $l = <$fh>;
	last if !defined $l;
	$l =~ s/\#[^'"';]*$//;	# attempt to strip comments
	$line++;
	if ($l =~ s/^\s*\<\://) {
	    my $begin = $line;
	    while ($l !~ s/\:\>\s*$//) {
		die "$pg->{src} line $begin: embedded code missing close quote ':>'"
		    if $fh->eof;
		my $tmp = <$fh>;
		$tmp =~ s/\#[^'"';]*$//;	# attempt to strip comments
		$l .= $tmp;
		$line++;
	    }
	    if ($l =~ m/^\s*\}/ or
		$l =~ m/^\s*my/ or
		$l =~ m/^\s*try_(?:read|update|abort_only)/) {
		$C .= "$l\n";
	    } elsif ($l =~ /^\s*sub\s*\{/) {
		$reply = "package $pg->{pkg}; $l";
		$reply_line = $begin;
	    } else {
		$C .= $prefix." $l;\n";
	    }
	} else {
	    $C .= $prefix.' q('. $l .");";
	}
    }
    $C .= ";1 };";     # return 1 if we have built a page
    if ($debug) {
	print "$pg->{src} " . "-"x(74-length($pg->{src})) . "\n";
	print "main : $C";
    }
    $pg->{main} = new Experimental::Eval($C, $pg->{src}, 0);
    if ($debug) {
	print "\n". "-"x75 . "\n";
	print "reply: $reply";
    }
    $pg->{reply} = new Experimental::Eval($reply, $pg->{src}, $reply_line);
    if ($debug) {
	print "\n". "-"x75 . "\n";
    }
    $pg->{mtime} = $st->mtime;
}

sub ok {
    my ($pg) = @_;
    defined $pg->{main} and defined $pg->{reply};
}

sub do_reply {
    my ($pg) = @_;
    $pg->{reply}->x() if $pg->{reply}->ok;
}

sub do_main {
    my ($pg) = @_;
    $pg->{main}->x();
}

package HTML::PHTML;
use strict;
use integer;
use Carp;
use vars qw($VERSION);

$VERSION='1.01';

sub new {
    my ($class, $dir) = @_;
    my $pkg = caller();
    my $o = bless { DIR => $dir, PACKAGE => $pkg, DEBUG=>0 }, $class;
    for my $f (glob("$dir/*.phtml")) {
	$f =~ s|^$dir/(.+)\.phtml$|$1|;
	$o->reload($f);
    }
    $o;
}

sub reload {
    my ($o, $name) = @_;
    $name =~ s/\.phtml$//;
    $o->{$name} ||= new HTML::PHTML::Page($o->{PACKAGE}, "$o->{DIR}/$name.phtml");
    my $pg = $o->{$name};
    $pg->reload($o->{DEBUG});
}

sub debug {
    my ($o, $yes) = @_;
    $o->{DEBUG} = $yes;
}

sub x {
    my ($o, $name) = @_;
    $name =~ s/\.phtml$//;
    $o->reload($name);
    my $pg = $o->{$name};
    die "Problems loading page '$name'" if !$pg->ok;
    my @replies = keys %$o;
    for my $k (@replies) {
	my $pg = $o->{$k};
	next if ref $pg ne 'HTML::PHTML::Page';  # hack XXX
	my $ret=0;
	$ret = $pg->do_reply;
	return $ret if $ret;
    }
    $pg->do_main;
}

1;
__END__;

=head1 NAME

HTML::PHTML - "Perl Embedded HTML" Page Cache

=head1 SYNOPSIS

    use vars qw($PHTML $B);
    require HTML::PHTML;

    $B = '';
    $PHTML = new HTML::PHTML("$FindBin::Bin/../lib/bm") if !$PHTML;
    $PHTML->x($page_name);
    print $B;

=head1 DESCRIPTION

This module is more useful when you also use FastCGI or
Apache/mod_perl.  If you are not using one of these packages yet,
investigate that first.

Most HTML::* modules are wrappers around string manipulation.  This
module actually does something:

For each C<$page_name>, the file C<$page_name.phtml> is loaded from
the given directory.  The code is executed and HTML is appended to
C<$B> in the calling package.  Optionally, per-page code is executed
before any page is built.

This is much more general and easy than HTML::Embperl and does not
need a separate binary like ePerl.

=head1 PAGE STRUCTURE

Raw HTML is copied as-is.  Perl code can be embedded by quoting it
with <: and :>.  The open quote must be placed at the beginning of a
line and the close quote is only recognized at the end of a line.

All of the perl code is C<eval>d in the same lexical block, so you may
declare lexical variables or write C<for> loops around the raw HTML.
Also note that the eval happens in the caller's package so you can
access all your usual globals and functions.

A few constructs are handled specially:

=over 4

=item * UNCAPTURED OUTPUT

Normally, perl code is assumed to evaluate to a string to be
immediately appended to the HTML buffer.  However, if the code starts
with a close brace, a C<my>, or an ObjStore transaction
(eg. C<try_read>), then the value of the perl code is ignored.

=item * REPLIES

A block of embedded perl code that starts with an anonymous sub
declaration is assumed to be a reply handler.  You can use reply
handlers to react a user response to an HTML form before the next page
is generated.

Normally, a reply handler should return false.  However, if a handler
redirects or generates the page itself, it should return true to stop
the execution of subsequent handlers or the generation of the default
next page.

=back

=head1 EXAMPLE: C<DEMO.PHTML>

 <body bgcolor="#ffffff" text="#000000" link="#000000" vlink="#000000" >
 <center><h1><big>
 <: small_caps("Mondo Server") :>
 </big></h1></center>
 <p>
 <hr><p>
 <font size=+2>With the help of these fantastic technologies,
 <div align=right>
 <: extern_href('<img src="/etc/perl_id_bw_sm.gif" border=0 >',
               'http://www.perl.org') :>
 <div align=left>
 <br>This sophisticated web application was written
 <div align=right>
 <: extern_href(qq(<img src="/etc/PoweredByOS.gif" border=0 >),
	       'http://www.odi.com') :>
 <div align=left>
 <br>In a mere <b>ten days</b>
 <div align=right>
 <: extern_href(qq(<img src="/etc/apache_logo.gif" border=0 >),
	       'http://www.apache.org') :>
 <div align=left>
 <br>With almost zero frustration!

 <: sub{
    if (is_cmd('login')) {
	my $loginUser = $p_in{'loginUser'};
	my $ok=0;
	try_update {
	    my $Users = $db->root('Users');
	    if (!exists $Users->{'index'}{$User}) {
		abort("'$User' is not a valid user.");
	    }
	    $u = $Users->{'index'}{$User};
	    $User = $u->name;
	    $ok=1;
	};
	die if ($@ and $@ !~ m/:abort:/);
	if ($ok) { return $PHTML->x('frameset'); }
    }
    0;
 } :>

=head1 BUGS

The parser should be slightly more customizable so we can factor out
the ObjStore specific stuff.

Listen to REFERER to avoid running through all the reply handlers?

Avoid globals?

=head1 AUTHOR

Copyright (c) 1997 Joshua Nathaniel Pritikin.  All rights reserved.

This package is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

Apache/mod_perl or FastCGI, C<ObjStore>, C<FindBin>, and C<Experimental::Eval>.

=cut
