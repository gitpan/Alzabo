package Alzabo::BackCompat;

use strict;

use Alzabo::Config;

use File::Basename;
use File::Copy;
use File::Spec;
use Storable;
use Tie::IxHash;

use Params::Validate qw( :all );
Params::Validate::validation_options( on_fail => sub { Alzabo::Exception::Params->throw( error => join '', @_ ) } );

#
# Each pair represents a range of versions which are compatible with
# each other.  The first one is not quite right but it has to start
# somewhere ;)
#
# Any extra elements are subroutines which should be run to update the
# schema, if it's version is lower than the first element of the
# version pair.
#
my @compat = ( [ 0, 0.64 ],
	       [ 0.65, $Alzabo::VERSION,
		 \&add_comment_fields,
	       ],
	     );

sub update_schema
{
    my %p = validate( @_, { name    => { type => SCALAR },
			    version => { type => SCALAR },
			  } );

    my @cb;
    foreach my $c (@compat)
    {
	return
	    if ( ( $p{version} >= $c->[0] &&
		   $p{version} <= $c->[1] ) &&

		 ( $Alzabo::VERSION >= $c->[0] &&
		   $Alzabo::VERSION <= $c->[1] )
	       );

	if ( $p{version} < $c->[0] && @$c > 2 )
	{
	    push @cb, @{$c}[2..$#$c];
	}
    }

    my $create_loaded;
    unless ( $Alzabo::Create::Schema::VERSION )
    {
	require Alzabo::Create::Schema;
	$create_loaded = 1;
    }

    my $v = $p{version} = 0 ? '0.64 or earlier' : $p{version};

    my $c_file = Alzabo::Create::Schema->_schema_filename( $p{name} );
    unless ( -w $c_file )
    {
	my $msg = <<"EOF";

The '$p{name}' schema was created by an older version of Alzabo
($v) than the one currently installed ($Alzabo::VERSION).

Alzabo can update your schema objects but your schema file:

  $c_file

is not writeable by this process.  Loading this schema in a process
which can write to this file will cause the schema to be updated.

EOF

	die $msg;
    }

    my $dir = dirname($c_file);
    unless ( -w $dir )
    {
	my $msg = <<"EOF";

The '$p{name}' schema was created by an older version of Alzabo
($v) than the one currently installed ($Alzabo::VERSION).

Alzabo can update your schema objects but its director:

  $dir

is not writeable by this process.  Loading this schema in a process
which can write to this file will cause the schema to be updated.

EOF

	die $msg;
    }

    foreach my $file ( glob("$dir/*.alz"),
		       glob("$dir/*.rdbms"),
		       glob("$dir/*.version") )
    {
	my $backup = "$file.bak.v$p{version}";

	copy($file, $backup);
    }

    my $fh = do { local *FH; *FH };
    open $fh, "<$c_file"
	or Alzabo::Exception::System->throw( error => "Unable to open $c_file: $!" );
    my $raw = Storable::retrieve_fd($fh);
    close $fh
	or Alzabo::Exception::System->throw( error => "Unable to close $c_file: $!" );

    $_->($raw) foreach @cb;

    open $fh, ">$c_file"
	or Alzabo::Exception::System->throw( error => "Unable to write to $c_file: $!" );
    Storable::nstore_fd( $raw, $fh )
	    or Alzabo::Exception::System->throw( error => "Can't store to filehandle" );
    close $fh
	or Alzabo::Exception::System->throw( error => "Unable to close $c_file: $!" );

    my $version_file =
	File::Spec->catfile( Alzabo::Config::schema_dir(),
			     $p{name}, "$p{name}.version" );

    open $fh, ">$version_file"
	or Alzabo::Exception::System->throw( error => "Unable to write to $version_file: $!" );
    print $fh $Alzabo::VERSION
	or Alzabo::Exception::System->throw( error => "Can't write to $version_file: $!" );
    close $fh
	or Alzabo::Exception::System->throw( error => "Unable to close $version_file: $!" );

    Alzabo::Create::Schema->load_from_file( name => $p{name} )->save_to_file;

    if ($create_loaded)
    {
	warn <<"EOF"

Your schema, $p{name}, has been updated to be compatible with the
installed version of Alzabo.  This required that the Alzabo::Create::*
classes be loaded.  If you were loading an Alzabo::Runtime::Schema
object, your running process is now somewhat larger than it has to be.

If this is a long running process you may want to reload it.

EOF
    }
}

sub add_comment_fields
{
    my $s = shift;

    foreach my $table ( $s->{tables}->Values )
    {
	$table->{comment} = '';

	foreach my $thing ( $table->{columns}->Values,
			    values %{ $table->{fk} } )
	{
	    $table->{comment} = '';
	}
    }
}

__END__

=head1 NAME

Alzabo::BackCompat - Convert old data structures

=head1 DESCRIPTION

This module is used to magically convert schemas with an older data
structure to the latest format.

More details on how this works can be found in L<the Backwards
Compatibility section|Alzabo/Backwards Compatibility>.

=cut
