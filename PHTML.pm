package HTML::PHTML::Page;
use strict;
use integer;
use Carp;
use IO::File;
use File::stat;

sub new {
    my ($class, $pkg, $src, $noappend) = @_;
    bless { pkg => $pkg, src => $src, noappend => $noappend }, $class;
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

    # It seems like switching packages invalidates the #line directive?
    # I didn't fully investigate it.

    my $C = qq'package $pg->{pkg}; sub {\n#line 1 "$pg->{src}"\n';
    my $line = 0;
    my $prefix = '$B.=';
    my $reply = 'sub {0}';
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
	    if ($pg->{noappend}->($l)) {
		$C .= "$l\n";
	    } elsif ($l =~ /^\s*sub\s*\{/) {
		$reply = qq'package $pg->{pkg};\n#line $begin "$pg->{src}"\n$l';
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
	print "main:\n$C";
    }
    $pg->{main} = eval $C;
    die if $@;
    if ($debug) {
	print "\n". "-"x75 . "\n";
	print "reply:\n$reply";
    }
    $pg->{reply} = eval $reply;
    die if $@;
    if ($debug) {
	print "\n". "-"x75 . "\n";
    }
    $pg->{mtime} = $st->mtime;
}

sub ok {
    my ($pg) = @_;
    $pg->{main} and $pg->{reply};
}

sub do_reply { $_[0]->{reply}->(); }
sub do_main { $_[0]->{main}->(); }

package HTML::PHTML;
use strict;
use integer;
use Carp;
use vars qw($VERSION);

$VERSION='1.03';

sub new {
    my ($class, $dir) = @_;
    my $noappend = sub {
	my $l = shift;
	($l =~ m/^\s*\}/ or
	 $l =~ m/^\s*my/ or
	 $l =~ m/^\s*try_(?:read|update|abort_only)/  #for ObjStore
	 );
    };
    my $pkg = caller();
    my $o = bless {
	dir => $dir, 'package' => $pkg, noappend => $noappend,
	debug=>0, initialized => 0, pages => {},
    }, $class;
    $o;
}

sub set_noappend { $_[0]->{noappend} = $_[1]; }

sub initialize {
    my ($o) = @_;
    return if $o->{initialized};
    $o->{initialized} = 1;
    for my $f (glob("$o->{dir}/*.phtml")) {
	$f =~ s|^$o->{dir}/(.+)\.phtml$|$1|;
	my $pg = $o->page($f);
	$pg->reload($o->{debug});
    }
}

sub debug {
    my ($o, $yes) = @_;
    $o->{debug} = $yes;
}

sub page {
    my ($o, $name) = @_;
    $name =~ s/\.phtml$//;
    $o->{pages}{$name} ||=
	new HTML::PHTML::Page($o->{'package'}, "$o->{dir}/$name.phtml",
			      $o->{noappend});
    $o->{pages}{$name};
}

sub x {
    my ($o, $name) = @_;
    $o->initialize;
    my $pg = $o->page($name);
    $pg->reload($o->{'debug'});
    die "Issues loading page '$name'" if !$pg->ok;
    for my $pg (values %{$o->{pages}}) {
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

    my $debug=1;
    $B = '';
    $PHTML = new HTML::PHTML("$FindBin::Bin/../lib/phtml", $debug) if !$PHTML;
    $PHTML->x($page_name);
    print $B;

=head1 DESCRIPTION

This module is more useful when you also use FastCGI or
Apache/mod_perl.  If you are not using one of these packages yet,
investigate that first.

For each C<$page_name>, the file C<$page_name.phtml> is loaded from
the given directory.  The code is executed and HTML is appended to
C<$B> in the calling package.  Optionally, per-page code is executed
before any page is built.

This is more general and easier than HTML::Embperl and does not
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

=head1 TODO

Use a search path instead of a single phtml directory.

=head1 BUGS

Listen to REFERER to avoid running through all the reply handlers?

Avoid globals?

=head1 AUTHOR

Copyright (c) 1997 Joshua Nathaniel Pritikin.  All rights reserved.
This package is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

Apache/mod_perl or FastCGI, C<ObjStore>, and C<FindBin>.

=cut
