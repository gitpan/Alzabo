#!/usr/bin/perl -w

use strict;

use Cwd;
use File::Basename;
use File::Path;

my @order = ( qw( Alzabo
		  Alzabo::Runtime
		  Alzabo::Runtime::Schema
		  Alzabo::Runtime::Table
		  Alzabo::Runtime::Row
		  Alzabo::Runtime::RowCursor
		  Alzabo::Runtime::Cursor
		  Alzabo::Runtime::JoinCursor
		  Alzabo::Runtime::Column
		  Alzabo::Runtime::ForeignKey
		  Alzabo::Runtime::Index
		  Alzabo::MethodMaker
		  Alzabo::ObjectCache
		),
	      [ qw( Alzabo::ObjectCache::MemoryStore
		    Alzabo::ObjectCache::NullSync
		    Alzabo::ObjectCache::DBMSync
		    Alzabo::ObjectCache::IPCSync
		  ) ],

	      qw( Alzabo::Exceptions
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

	      qw( Alzabo::ChangeTracker
		  Alzabo::Util
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
    elsif ( -f _ && substr($thing, -3) eq '.pm' )
    {
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
    $module =~ s,^.*(?=Alzabo),, or return;
    return if $module =~ /PreInstall/;
    $module =~ s/\.pm//;

    my $out = "$to/$module.html";

    my $dir = dirname($out);
    mkpath($dir) unless -d $dir;

    print "Creating $out\n";

    system("perl5.6.0 /usr/bin/pod2html --infile=$in --outfile=$out --htmlroot=$htmlroot")
	and die "error: $!\n";

    add_header($out);

    $made{$out} = 1;
}

sub add_header
{
    my $file = shift;

    local *FILE;
    open FILE, "$file"
	or die "Can't open $file: $!\n";

    my $html = join '', <FILE>;

    close FILE;

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
    $html =~ s,HTML::Mason,<a href="http://www.masonhq.com">HTML::Mason</a>,g;
    $html =~ s,(#.*)E<gt>(.*\n),$1>$2,gi;

    open FILE, ">$file"
	or die "Can't write to $file.pm: $!\n";

    print FILE $html;

    close FILE;
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
retrieve/change data in an RDBMS and that the reader will be using the
included schema creation interface to generate the schema objects,
rather then doing it themselves in pure Perl, then please see the <a
href="$htmlroot/Alzabo.html#what to read?">"What to Read?"</a> section.
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

    local *MOD;
    open MOD, "$from/$file.pm"
	or die "Can't open $from/$file.pm: $!\n";

    my $mod = join '', <MOD>;

    close MOD;

    my ($desc) = $mod =~ /=head1 NAME\n+[\w:]+\s+-\s+(.*)\n/;

    return $desc;
}
