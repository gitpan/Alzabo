#!/usr/bin/perl -w

use strict;

use File::Basename;
use File::Copy;
use File::Path;

my ($sourcedir, $libdir) = @ARGV;

foreach ($sourcedir, $libdir) { s,/$,,; }

foreach ( qw( Schema Table Column ColumnDefinition Index ForeignKey ) )
{
    my $from = "$sourcedir/Alzabo/$_.pm";

    foreach my $class ( qw( Create Runtime ) )
    {
	my $merge = "$sourcedir/Alzabo/$class/$_.pm";
	my $to = "$libdir/Alzabo/$class/$_.pm";
	merge( $from, $merge, $to, $class );
    }
}

merge( "$sourcedir/Alzabo.pm", "$sourcedir/Alzabo/QuickRef.pod", "$libdir/Alzabo/QuickRef.pod" );

sub merge
{
    my ($f, $t_in, $t_out, $class) = @_;

    local (*FROM, *TO);
    open FROM, $f or die "Can't read '$f': $!";
    open TO, $t_in or die "Can't read '$t_in': $!";

    my $from = join '', <FROM>;
    my $to = join '', <TO>;

    close FROM or die "Can't close '$f': $!";
    close TO or die "Can't close '$t_in': $!";

    $to =~ s/\r//g;
    $to =~ s/\n
             =for\ pod_merge   # find this string at the beginning of a line
             (?:
              \s*
              (\w+)            # optionally say what POD marker to merge until
             )
	     \s+
             (\w+)             # what we're going to merge (and replace)
             \n*
             (?=
              \n=              # next =foo marker, skipping all spaces
             )
             /
              find_chunk($f, $from, $1, $class, $2)
             /gxie;

    mkpath( dirname($t_out) ) unless -d dirname($t_out);

    if (-e $t_out)
    {
	chmod 0644, $t_out or die "Can't chmod '$t_out' to 644: $!";
    }
    open TO, ">$t_out" or die "Can't write to '$t_out': $!";
    print TO $to or die "Can't write to '$t_out': $!";
    close TO or die "Can't write to '$t_out': $!";
    chmod 0444, $t_out or die "Can't chmod '$t_out' to 444: $!";

    for ( $f, $t_out ) { s,^.*(?=Alzabo),,; s/\.pm$//; s,/,::,g; }

    print STDERR "merged $f docs into $t_out\n";
}

sub find_chunk
{
    my ($file, $from, $title, $class, $until) = @_;

    my $chunk;
    if ($title eq 'merged')
    {
	$chunk = "\n\nNote: all relevant documentation from the superclass has been merged into this document.\n";
    }
    else
    {
        if ( my ($l) = $from =~ /\n=head([1234]) +$title.*?\n/ )
	{
	    my $levels = join '', (1..$l);
	    my $until_re = $until ? qr/$until/ : qr/(?:head[$levels]|cut)/;
	    my $re = qr/(\n=head$l +$title.*?)\n=$until/s;
	    ($chunk) = $from =~ /$re/;
	}
    }

    if (defined $class)
    {
	$chunk =~ s/Alzabo::(Column|ColumnDefinition|ForeignKey|Index|Schema|Table)/Alzabo::$class\::$1/g;
    }

    die "Can't find =headX $title in $file\n" unless $chunk;
    return $chunk;
}
