#!/usr/bin/perl -w

use strict;

package QuickRef::Parser;

use Pod::Parser;

@QuickRef::Parser::ISA = qw(Pod::Parser);

sub command
{
    my $self = shift;
    my ($cmd, $text, $line, $para) = @_;

    $text =~ s/\s*$//;

    if ( $self->{in_table} && ! $self->{in_over} && $self->{last_was_text} )
    {
	$self->{_html} .= "</td></tr>\n";
    }

    if ($cmd =~ /head(\d)/)
    {
	my $level = $1;

	if ($level > 3)
	{
	    $self->{_html} .= "<h$level>$text</h$level>\n";
	    return;
	}

	if ($self->{in_table})
	{
	    $self->{_html} .= "</table>\n<br><br>";
	}

	$self->{_html} .= qq|<a name="$text">|;

	if ($level == 3)
	{
	    $self->{_html} .= qq|<table width="100%" border="1" cellpadding="4">\n|;
	    $self->{in_table} = 1;
	}
	elsif ($level < 3)
	{
	    $self->{in_table} = 0;
	    $self->{in_items} = 0;
	}

	if ($self->{in_table})
	{
	    $self->{_html} .= qq|<tr valign=top><td colspan="4">\n|;
	}

	$self->{_html} .= "\n<h$level>$text</h$level>\n";

	if ($self->{in_table})
	{
	    $self->{_html} .= "</td></tr>\n";
	}

	$self->{last_head} = $level;
    }
    elsif ($cmd eq 'over')
    {
	$self->{_html} .= "<tr valign=top><th>method</td><th>class/object</td><th>description</td><th>more info</td></tr>\n";
	$self->{in_over} = 1;
    }
    elsif ($cmd eq 'back')
    {
	$self->{in_over} = 0;
    }
    elsif ($cmd eq 'item')
    {
	$text =~ s/\* //;

	$self->{_html} .= qq|<a name="$text">|;

	if ($text =~ /(\w+)\s+(\(.*?\))/)
	{
	    $text = "$1\n $2";
	}

	$self->{_html} .= "<tr valign=top><td><pre>$text</pre></td>\n";
    }
    elsif ($cmd eq 'for')
    {
	if ( my ($col, $info) = $text =~ /\s*html\s+(\w+)=([^\n]+)/ )
	{
	    if ($col eq 'link')
	    {
		$self->{_html} .= "</td>";
	    }

	    $info =~ s,C<(.*?)>,<code>$1</code>,g;
	    $info =~ s!L<((?:<code>)?.*?(?:</code>)?)\|([^>]*)>!$self->_make_link($1,$2)!eg;
	    $info =~ s/E<(.*?)>/&$1;/g;

	    $self->{_html} .= "<td>$info</td>";
	    $self->{_html} .= "</tr>\n" if $col eq 'link';
	    $self->{last_col} = $col;
	}
    }

    $self->{last_was_text} = 0;
}

sub verbatim
{
    my $self = shift;
    my ($text, $line, $para) = @_;

    $self->{_html} .= "<pre>$text</pre>";
}

sub textblock
{
    my $self = shift;
    my ($text, $line, $para) = @_;

    $text =~ s/\s*$//;

    $text =~ s,B<(.*?)>,<strong>$1</strong>,g;
    $text =~ s,C<(.*?)>,<code>$1</code>,g;
    $text =~ s!L<((?:<code>)?.*?(?:</code>)?)\|([^>]*)>!$self->_make_link($1,$2)!eg;
    $text =~ s/E<(.*?)>/&$1;/g;

    if ($self->{in_table} && ! $self->{last_was_text})
    {
	if ($self->{in_over})
	{
	    $self->{_html} .= "<td>";
	}
	else
	{
	    $self->{_html} .= q|<tr valign=top><td colspan="4">|;
	}
    }

    $self->{_html} .= "<p>$text</p>\n";

    $self->{last_was_text} = 1;
}

sub _make_link
{
    my $self = shift;
    my $linktext = shift;
    my $link = shift;

    if ($link =~ m,/,)
    {
	$link =~ s,/,.html#,;
    }
    else
    {
	$link .= '.html';
    }
    $link =~ s,::,/,g;

    return qq|<a href="$self->{_htmlroot}/$link">$linktext</a>|;
}

sub interior_sequence
{
    my $self = shift;
    my ($cmd, $arg, $seq) = @_;

}

package main;

use Cwd;
use File::Basename;
use File::Path;

my @order = ( qw( Alzabo
		  Alzabo::MySQL
		  Alzabo::PostgreSQL
		  Alzabo::QuickRef
		  Alzabo::Runtime
		  Alzabo::Runtime::Schema
		  Alzabo::Runtime::Table
		  Alzabo::Runtime::Row
		  Alzabo::Runtime::RowCursor
		  Alzabo::Runtime::Cursor
		  Alzabo::Runtime::JoinCursor
		  Alzabo::Runtime::OuterJoinCursor
		  Alzabo::Runtime::PotentialRow
		  Alzabo::MethodMaker
                  Alzabo::Runtime::ForeignKey
		  Alzabo::Runtime::Column
		  Alzabo::Runtime::Index
		  Alzabo::ObjectCache
		  Alzabo::Exceptions
                  Alzabo::FAQ
		  Alzabo::Create::Schema
		  Alzabo::Create::Table
		  Alzabo::Create::Column
		  Alzabo::Create::ColumnDefinition
		  Alzabo::Create::ForeignKey
		  Alzabo::Create::Index
		  Alzabo::Driver
		),
	      [ qw( Alzabo::Driver::MySQL Alzabo::Driver::PostgreSQL ) ],

	      'Alzabo::RDBMSRules',
	      [ qw( Alzabo::RDBMSRules::MySQL Alzabo::RDBMSRules::PostgreSQL ) ],

	      'Alzabo::SQLMaker',
	      [ qw( Alzabo::SQLMaker::MySQL Alzabo::SQLMaker::PostgreSQL ) ],

	      qw( Alzabo::Config
                  Alzabo::ChangeTracker
		  Alzabo::ObjectCache::Sync
		  Alzabo::Schema
		  Alzabo::Table
		  Alzabo::Column
		  Alzabo::ForeignKey
		  Alzabo::Index
		  Alzabo::ColumnDefinition
		  Alzabo::Runtime::ColumnDefinition
		  Alzabo::Create
		),
	    );

unless (@ARGV == 3)
{
    print "\nUsage: make_html_docs.pl  [in/dir]  [out/dir]  [/url/root]\n\n";
    exit;
}

my $cwd = cwd();
my ($from, $to, $htmlroot) = @ARGV;
foreach ($from, $to) { s,/$,,; s,(.*),$cwd/$1, unless substr($_, 0, 1) eq '/'; }

my $temp;
foreach ( $ENV{TEMP}, "$ENV{HOME}/tmp", '/tmp' )
{
    if (defined $_ && -d)
    {
	$temp = $_;
	last;
    }
}

die "Can't find a temp dir to write to\n" unless defined $temp;
system( "$^X $cwd/pod_merge.pl $from $temp" )
    and die "$^X $cwd/pod_merge.pl $from $temp failed: $!\n";

my $version;
get_version();

my %made;
convert($from, 1);
convert("$temp/Alzabo");
make_quickref();
make_index();

sub get_version
{
    local *ALZ;
    open ALZ, "$from/Alzabo.pm"
	or die "Can't open $from/Alzabo.pm: $!";

    while (<ALZ>)
    {
	if (/\$VERSION = (.*)\n/)
	{
	    eval "\$version = $1";
	    die $@ if $@;

	    close ALZ;
	    return;
	}
    }
}

sub convert
{
    my $thing = $_[0];

    if ( -d $thing )
    {
	convert_dir(@_);
    }
    elsif ( -f _ && ( substr($thing, -3) eq '.pm' || substr($thing, -4) eq '.pod' ) )
    {
	return if $thing =~ /QuickRef/;
	if ($_[1])
	{
	    my $skip = $thing;
	    $skip =~ s,.*(?=Alzabo),,;
	    return if -e "$temp/$skip";
	}
	pod2html($thing);
    }
}

sub convert_dir
{
    my $dir = shift;

    local *DIR;

    opendir DIR, $dir;

    my @e = readdir DIR;

    closedir DIR;

    foreach my $e (@e)
    {
	next if substr($e, 0, 1) eq '.';
	convert("$dir/$e", @_);
    }
}

sub pod2html
{
    my $in = shift;

    my $module = $in;
    $module =~ s/PreInstall/Alzabo/;

    $module =~ s,^.*(?=Alzabo),, or return;
    $module =~ s/\.p(?:m|od)//;

    my $out = "$to/$module.html";

    my $dir = dirname($out);
    mkpath($dir) unless -d $dir;

    print "Creating $out\n";

    system("$^X /usr/bin/pod2html --infile=$in --outfile=$out --htmlroot=$htmlroot")
	and die "error: $!\n";

    fixup_html($out);

    $made{$out} = 1;
}

sub fixup_html
{
    my $file = shift;

    local *FILE;
    open FILE, "$file"
	or die "Can't open $file: $!\n";

    my $html = join '', <FILE>;

    close FILE;

    $html = add_header($file, $html);

    $html =~ s,<code>(value\(s\))</code>,$1,gi;
    $html =~ s,<code>(integer\(\d+\))</code>,$1,gi;
    $html =~ s,HTML::Mason,<a href="http://www.masonhq.com">HTML::Mason</a>,gi;
    $html =~ s,(#.*)E<gt>(.*\n),$1>$2,gi;
    $html =~ s,E&lt;gt&gt;,>,gi;
    $html =~ s,E&lt;lt&gt;,<,gi;

    $html =~ s,<hr>\s*<p>\s*<hr>,<hr>,gi;

    if ( $file =~ m,Runtime/Table\.html, )
    {
	print "  Fixing up links in $file\n";

	$html =~ s,<em>(?:Alzabo/)?Using SQL functions</em>,<a href="$htmlroot/Alzabo.html#using%20sql%20functions">Using SQL functions</a>,gi;
    }
    elsif ( $file =~ m,Runtime/PotentialRow\.html, )
    {
	print "  Fixing up links in $file\n";

	$html =~ s,<em>referential integrity constraints</em>,<a href="$htmlroot/Alzabo.html#referential%20integrity">referential integrity constraints</a>,gi;
    }

    open FILE, ">$file"
	or die "Can't write to $file: $!\n";

    print FILE $html;

    close FILE;
}

sub add_header
{
    my ($file, $html) = @_;

    my $module = $file;
    $module =~ s,.*(?=Alzabo),,;
    $module =~ s/\.html$//;
    $module =~ s,/,::,g;

    my $header = <<"EOF";
<p>
<div align="center">
<h2>Alzabo (version $version) - $module</h2>
</div>
</p>

<p>
<a href="$htmlroot">Index</a>
</p>

<hr>

EOF
    $html =~ s/(<body>\n)/$1\n$header/i;

    return $html;
}

sub make_index
{
    my $html = <<"EOF";
<html>
<head>
<title>Alzabo Documentation Index</title>
</head>

<body>
<h1>Alzabo Documentation Index (version $version)</h1>

<p>
If you are most interested in using Alzabo as an interface to
retrieve/change data in an RDBMS and you will be using the included
schema creation interface to generate the schema objects, rather then
doing it yourself in pure Perl, then please see the <a
href="$htmlroot/Alzabo.html#what to read">"What to Read?"</a>
section.
</p>

<p>
If you are interested in reverse engineering an existing schema into
Alzabo objects, then documentation on this subject can be found in
Alzabo::Create::Schema.
</p>

<ul>
EOF

    my %index;
    foreach my $file (sort keys %made)
    {
	$file =~ s,.*(?=Alzabo),,;
	my $module = $file;
	$module =~ s/\.html$//;
	$module =~ s,/,::,g;
	$index{$module} = "$htmlroot/$file";
    }


    foreach my $module (@order)
    {
	unless (ref $module)
	{
	    my $desc = module_description($module);
	    $html .= qq| <li><a href="$index{$module}">$module</a> - $desc\n|;
	}
	else
	{
	    $html .= "  <ul>\n";
 	    foreach my $subclass (@$module)
	    {
		my $desc = module_description($subclass);
		$html .= qq|   <li><a href="$index{$subclass}">$subclass</a> - $desc\n|;
	    }
	    $html .= "  </ul>\n";
	}
    }

    my $time = localtime;

    $html .= <<"EOF";
</ul>

<p>
Index generated: $time
</p>

</body>
</html>
EOF

    print "Creating $to/index.html\n";

    local *INDEX;
    open INDEX, ">$to/index.html"
	or die "Can't write to $to/index.html: $!\n";

    print INDEX $html;

    close INDEX;
}

sub module_description
{
    my $file = shift;
    $file =~ s,::,/,g;

    $file =~ s/Alzabo/PreInstall/ if $file =~ /Config/;

    my $ext = -e "$from/$file.pm" ? 'pm' : 'pod';

    local *MOD;
    open MOD, "$from/$file.$ext"
	or die "Can't open $from/$file.$ext: $!\n";

    my $mod = join '', <MOD>;

    close MOD;

    my ($desc) = $mod =~ /=head1 NAME\s*\n+[\w:]+\s+-\s+(.*)\n/;

    unless (defined $desc)
    {
	($desc) = $mod =~ /=head1 NAME\s*\n+(.*)\n/;
    }

    return $desc;
}

sub make_quickref
{
    my $from = "$temp/Alzabo/QuickRef.pod";
    my $to = "$to/Alzabo/QuickRef.html";

    my $p = QuickRef::Parser->new;

    $p->{_htmlroot} = $htmlroot;
    $p->parse_from_file($from);

    my $html = <<"EOF";
<html>
<head>
<title>Alzabo Method Quick Reference</title>
</head>
<body>

<p>
<div align="center">
<h2>Alzabo (version $version) - Method Quick Reference</h2>
</div>
</p>

<p>
<a href="$htmlroot">Index</a>
</p>

<hr>

EOF

    $html .= $p->{_html};
    $html .= "\n</body></html>";

    $html =~ s/<a name="NAME">\s+<h1>.*?<h1>/<h1>/gs;

    print "Creating $to\n";

    open FILE, ">$to"
	or die "Cannot write to $to: $!";
    print FILE $html
	or die "Cannot write to $to: $!";
    close FILE;

    $made{$to} = 1;
}

