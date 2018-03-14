#!/usr/bin/env perl

########################################################################
#
#  START COPYRIGHT-NOTICE: 2003-2004
#
#  Copyright (c) 2003-2004 VERITAS Software Corporation. All rights reserved.
#  VERITAS,  the VERITAS Logo  and all other  VERITAS product names  and
#  slogans are trademarks  or registered trademarks of  VERITAS Software
#  Corporation.  VERITAS and the VERITAS Logo Reg.  U.S. Pat. & Tm. Off.
#  Other product names and/or slogans mentioned herein may be trademarks
#  or registered trademarks of their respective companies.
#
#  UNPUBLISHED -  RIGHTS RESERVED UNDER THE COPYRIGHT LAWS OF THE UNITED
#  STATES.  USE OF A COPYRIGHT NOTICE IS PRECAUTIONARY ONLY AND DOES NOT
#  IMPLY PUBLICATION OR DISCLOSURE.
#
#  THIS SOFTWARE CONTAINS CONFIDENTIAL INFORMATION  AND TRADE SECRETS OF
#  VERITAS  SOFTWARE.  USE,  DISCLOSURE OR  REPRODUCTION  IS  PROHIBITED
#  WITHOUT THE PRIOR EXPRESS WRITTEN PERMISSION OF VERITAS SOFTWARE.
#
#  The Licensed Software and Documentation are deemed to be  "commercial
#  computer software"  and  "commercial computer software documentation"
#  as defined in FAR Sections 12.212 and DFARS Section 227.7202.
#
#  END COPYRIGHT-NOTICE.
#
########################################################################

use strict;
use warnings;
use English;
use Cwd;
use integer;
use Getopt::Std;
use POSIX 'setsid';

# Constants
#
my $FOREVER      = 1;
my $FALSE        = 0;
my $TRUE         = 1;
my $MAX_PERCENT  = 20;
my $TEST_DIR     = "load_dir";
my @CHUNK_N_DATA = (0) x 1024 x 100;    # 100K block

# Usage output
#
sub usage {

    my ($ret_err) = @_;

    print STDERR << "USAGE_END";

Usage: $PROGRAM_NAME -d <dir> [-h]

Notes:
	-d <base dir>  : The location that the test will be run on.
	-t <test_dir>  : The directory were are files will be created
	-h             : This message

USAGE_END

    exit $ret_err;

}

# Get arguments and make sure they are correct.
#
my %args;
getopts( "d:t:h", \%args );

return usage(0) if ( $args{h} );

usage(1) unless ( defined $args{d} );
usage(1) unless ( -d $args{d} );

my $test_dir = ( defined $args{t} ) ? $args{t} : $TEST_DIR;

# This is the directory we will be doing all our writing in.
#
my $base_dir = "$args{d}/$test_dir";

# Go to the test directory
#
mkdir $base_dir;
chdir $base_dir or die "Can't cd to $base_dir";
system("rm -r $base_dir/*");

my @dir_list = ();    # list of our dirs.
my $cnt      = 0;     # number of files we've made
my $cwd;              # Our current working dir we are filling.

# Before we go into our infinite loop, put this process in the background
# and set init (pid 1) as it's parent.  To avoid zombies - which are always
# best avoided.
#

defined( my $pid = fork ) or die "Cannot fork: $!\n";

if ($pid) {

    # parent so just return the pid and die.
    $| = 1;
    print $pid, "\n";
    exit 0;

}

# We're now the child. Lets cut all ties to our fokes.
#
chdir '/' or die "Can't chdir to /: $!";
open STDIN,  '/dev/null'  or die "Can't read /dev/null: $!";
open STDOUT, '>/dev/null' or die "Can't write to /dev/null: $!";
open STDERR, '>/tmp/log'  or die "Can't write to /tmp/log: $!";
setsid or die "Can't start a new session: $!";

while ($FOREVER) {

    # put every 100 files in a different dir
    #
    if (
        !( $cnt % 100 ) or    # have we made 100 files yet?
        ( $cnt / 100 ) ne $cwd
      )                       # are we in the dir we want to be?
    {

        # add the "deleteable" dir to the list
        #
        push @dir_list, ("$base_dir/$cwd") if ( defined $cwd );

        # Now make a new one.
        #
        $cwd = $cnt / 100;
        mkdir "$base_dir/$cwd"
          or die "Couldn't create $base_dir/$cwd";

        chdir "$base_dir/$cwd"
          or die "Can't cd to $base_dir/$cwd";

    }

    # Make a file
    #
    open FILE, "> file_$cnt" or die "Can't open file_$cnt: $!";
    print FILE @CHUNK_N_DATA;
    close FILE;

    # if we hit our data ceiling delete a file
    #
    my @output = `df -k $base_dir`;
    my $percent;
    for (@output) {
        /\s+(\d+)\s*%\s+/ and do { $percent = $1; last; };
    }

    if (
        ( $percent > $MAX_PERCENT ) and    # Reach or target size?
        ( @dir_list > 1 )                  # Have an extra dir to delete?
      )
    {
        my $dir_to_nuke = pop @dir_list;

        die "can't rm -r $dir_to_nuke"
          unless ( system("rm -r $dir_to_nuke 2> /dev/null") == 0 );
    }

    # go one to the next file
    #
    $cnt++;

}
