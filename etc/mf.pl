#!/usr/bin/env perl

#
########################################################################
#
# $Id: mf.pl,v 1.2 2007/06/05 20:12:21 srp Exp $
#ident "$Source: /src/cluster/vcstest/src/smtf/lib/SWIFT/bin/mf.pl,v $"
# $Author: srp $
# $Date: 2007/06/05 20:12:21 $
#
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

use strict;
use warnings "all";
use Getopt::Std;            # Processing mf.pl's option from command line
use Errno qw(EAGAIN);       # for fork()
use POSIX ":sys_wait_h";    # for waitpid()

# Global variables
use vars qw/ %opts /;

my %mf_args = (
    "mf_dir"          => undef,    # Directory to create files in
    "mf_workers"      => 2,        # Default # of workers is 2
    "mf_files"        => 1e2,      # Default # of files is 1 million
    "mf_fsize"        => 1024,     # Default file's size in byte
                                   # When -T is ON, mf_fsize is in kbyte
    "mf_rand_fsize"   => 0,        # Random file's size up to mf_fsize
    "mf_header"       => 2,        # -h (kbyte) for odm and qio utilities
    "mf_setext"       => 0,        # Use setext(1M) to create files
    "mf_prefix"       => "",       # prefix for file names
    "mf_worker_func"  => 0,        # Worker func to call to get work done
    "mf_create_file"  => 0,        # Function to create setext/ascii file
    "mf_worker_task"  => [],       # attributes specific to each worker
    "mf_func_to_call" => 0,        # Which million files layout to call
    "mf_horizontal"   => 0,        # # of horizontal dirs to create
    "mf_vertical"     => 0,        # # of vertical dirs (OS dependent)
    "mf_verbose"      => 0         # Print debugging information
);

my ($progname);
my ( $setext_cmd, $odm_cmd, $qio_cmd );
my ( $which_mf, $mf_funcname );
my ($getoptret);
my ($mf_retcode);

$progname = $0;
$progname =~ s/^(.*)\///;

# Default values
$setext_cmd = '/opt/VRTS/bin/setext';
$odm_cmd    = '/opt/VRTS/bin/odmmkfile';
$qio_cmd    = '/opt/VRTS/bin/qiomkfile';

sub dpp_mf_usage(;$) {

    my ($opt_help) = @_;

    print STDERR << "MF_USAGE";

Usage:	$progname -d {<dir> | <mount-point>}
	[-w <#ofworkers>]
	[-n <#offiles>]
	[-s <file's size in byte>]
	[-R]
	[-B <horizontal directories>]
	[-D <vertical directories>]
	[-H <header's size in kbyte>]
	[-T]
	[-L {M | B | D | R | O}]
	[-v]
	[-h]

Notes:
	The -d is mandatory (existing directory to put those files)
	In -w, the default value for <#ofworkers> is 2
	In -n, the default value for <#offiles> is 1 million
	All the files created using -s have the same <file's size>
	The -R creates random file's size with <file's size> as largest
	The -B creates the number of directories horizontally (default is 1024)
	Other options effected by -B are -L B and -L R
	The -D creates the number of directories vertically (default is 1024)
	Other options effected by -D are -L D and  -L R
	The -H <header's size in kbyte> is for qiomkfile or odmmkfile utilities

	Environment variable DPP_MF_WORKERS takes precedence over -w

	The -T option uses the setext(1M) utility to create all files
	File's size (in -s) is in multiple of 1024 bytes when -T is specified

	The -L M creates <#offiles> files in a directory
	The -L B creates <#offiles> files in multiple directories (horizontal)
	The -L D creates <#offiles> files in multiple directories (vertical)
	The -L R creates <#offiles> in random number of directories (B & D)
	The -L O creates <#offiles> using odmmkfile(1), qiomkfile(1), setext(1)

	When the -L option is not specified, the -L M is the default

	The -v prints debugging information

	The -h is the customary help option

	The default number of workers ought to be derived from the number
	of physical processors that are online.  Specifying a number of 
	worker that is larger than the number of online physical processor
	has detrimental effect.  [On a system with two online processors,
	3 workers take 40 minutes and 2 workers take 30 minutes to create
	one million files (1K size).]

MF_USAGE

    if ( defined($opt_help) && $opt_help ne '' ) {
        exit(0);
    }
    else {
        exit(1);
    }
}

sub dpp_mf_create_setext($$) {

    my ( $mf_fname, $kbytes ) = @_;
    my ($setext_rc);

    $mf_fname = $mf_fname;

    # mf_fname is a file with full path name.
    $setext_rc =
      system( "touch $mf_fname; "
          . "$setext_cmd -r ${kbytes}k -f chgsize $mf_fname" );
    if ( $setext_rc != 0 ) {
        print STDERR "setext(${mf_fname}) failed -- $setext_rc\n";
        return 0;
    }

    return 1;
}

sub dpp_mf_create_odm($$$) {

    my ( $fname, $kbytes, $header ) = @_;
    my ($odm_rc);

    $fname = $fname;

    # fname is a file with full path name.
    $odm_rc = system("$odm_cmd -h ${header}k -s ${kbytes}k $fname");
    if ( $odm_rc != 0 ) {
        print STDERR "${odm_cmd}(${fname}) failed -- $odm_rc\n";
        return 0;
    }

    return 1;
}

sub dpp_mf_create_qio($$$) {

    my ( $fname, $kbytes, $header ) = @_;
    my ($qio_rc);

    $fname = $fname;

    # fname is a file with full path name.
    $qio_rc = system("$qio_cmd -h ${header}k -s ${kbytes}k $fname");
    if ( $qio_rc != 0 ) {
        print STDERR "${qio_cmd}(${fname}) failed -- $qio_rc\n";
        return 0;
    }

    return 1;
}

sub dpp_mf_create_ascii($$) {

    my ( $mf_fname, $mf_fsize ) = @_;
    my ($bytes);

    $mf_fname = $mf_fname;

    # mf_fname is a file with full path name.
    unless ( open( MF, "> $mf_fname" ) ) {
        print STDERR "open(${mf_fname}) failed -- $!\n";
        return 0;
    }

    # chr(65) == 'A' chr(90) == 'Z'
    # chr(97) == 'a' chr(122) == 'z'
    $bytes = chr( 65 + int( rand() * 128 ) % 57 );
    print MF $bytes x $mf_fsize;
    close(MF);

    return 1;
}

sub dpp_mf_worker($;$) {
    my ( $mfptr, $worker ) = @_;

    my ( $i, $start, $end, $bytes );

    $start = $mfptr->{mf_worker_task}[$worker]{mf_start};
    $end   = $mfptr->{mf_worker_task}[$worker]{mf_end};

    for ( $i = $start ; $i < $end ; $i++ ) {

        # Recompute the mf_fsize if mf_rand_fsize is ON ???
        $bytes = $mfptr->{mf_fsize};

        if (
            !$mfptr->{mf_create_file}(
                "$mfptr->{mf_dir}/$mfptr->{mf_prefix}_${worker}_$i", $bytes ) )
        {
            print STDERR "Worker $worker open($i) failed\n";
            return 1;
        }
    }

    return 0;
}

sub dpp_bmf_worker($;$) {
    my ( $mfptr, $worker ) = @_;

    my ( $i,       $start,     $end );
    my ( $fsize,   $diri,      $numofdir, $pname );
    my ( $entries, $remainder, $dirstart, $dirend );

    # Each worker is to create its portion of the horizontal directories.
    $entries   = int( $mfptr->{mf_horizontal} / $mfptr->{mf_workers} );
    $remainder = int( $mfptr->{mf_horizontal} % $mfptr->{mf_workers} );

    # The starting and ending directories for this worker.
    $dirstart = $worker * $entries;
    $dirend   = $entries + $dirstart;

    if ( $worker == ( $mfptr->{mf_workers} - 1 ) && $remainder > 0 ) {

        # The last worker has to do more -- remaining slots
        $dirend += $remainder;
    }

    $numofdir = $dirend - $dirstart;

    $pname = $mfptr->{mf_prefix};

    # Create the horizontal directories.
    for ( $i = $dirstart ; $i < $dirend ; $i++ ) {
        if ( !mkdir("$mfptr->{mf_dir}/${pname}$i") ) {
            print STDERR
              "bmf:1 mkdir($mfptr->{mf_dir}/${pname}$i) failed -- $!\n";
            return 1;
        }
    }

    $start = $mfptr->{mf_worker_task}[$worker]{mf_start};
    $end   = $mfptr->{mf_worker_task}[$worker]{mf_end};

    for ( $i = $start ; $i < $end ; $i++ ) {

        # Recompute the mf_fsize if mf_rand_fsize is ON ???
        $fsize = $mfptr->{mf_fsize};

        # Find the directory this file will be created in.
        $diri = $dirstart + ( int( rand() * $numofdir ) % $numofdir );

        if (
            !$mfptr->{mf_create_file}(
                "$mfptr->{mf_dir}/${pname}$diri/${pname}_${worker}_$i", $fsize )
          )
        {
            print STDERR "bmf:2 Worker $worker open($i) failed\n";
            return 1;
        }
    }

    return 0;
}

sub dpp_dmf_worker($;$) {
    my ( $mfptr, $worker ) = @_;

    my ( $i, $j, $start, $end );
    my ( $fsize, $diri, $dirname, $numofdir, $pname );

    $start = $mfptr->{mf_worker_task}[$worker]{mf_start};
    $end   = $mfptr->{mf_worker_task}[$worker]{mf_end};

    $numofdir = $mfptr->{mf_vertical};
    $pname    = $mfptr->{mf_prefix};

    for ( $i = $start ; $i < $end ; $i++ ) {

        # Recompute the mf_fsize if mf_rand_fsize is ON ???
        $fsize = $mfptr->{mf_fsize};

        # Find the directory this file will be created in.
        $diri = int( rand() * $numofdir ) % $numofdir;

        $dirname = '';
        for ( $j = 0 ; $j <= $diri ; $j++ ) {
            $dirname .= "/${pname}$j";
        }

        if (
            !$mfptr->{mf_create_file}(
                "$mfptr->{mf_dir}${dirname}/${pname}_${worker}_$i", $fsize ) )
        {
            print STDERR "Worker $worker open($i) failed\n";
            return 1;
        }
    }

    return 0;
}

sub dpp_rmf_worker($;$) {
    my ( $mfptr, $worker ) = @_;

    my ( $i, $j, $start, $end );
    my ( $horizontal, $vertical, $hname, $vname, $pname, $hdir, $vdir );
    my ( $dirname, $numofdir, $fsize );
    my ( $entries, $remainder, $dirstart, $dirend );
    my ($mkdir_rc);

    # Each worker is to create its portion of the horizontal directories.
    $horizontal = $mfptr->{mf_horizontal};

    $entries   = int( $horizontal / $mfptr->{mf_workers} );
    $remainder = int( $horizontal % $mfptr->{mf_workers} );

    # The starting and ending directories for this worker.
    $dirstart = $worker * $entries;
    $dirend   = $entries + $dirstart;

    if ( $worker == ( $mfptr->{mf_workers} - 1 ) && $remainder > 0 ) {

        # The last worker has to do more -- remaining slots
        $dirend += $remainder;
    }

    $numofdir = $dirend - $dirstart;

    $hname = 'bmf';

    # Create the horizontal directories.
    for ( $i = $dirstart ; $i < $dirend ; $i++ ) {
        if ( !mkdir("$mfptr->{mf_dir}/${hname}$i") ) {
            print STDERR
              "rmf:1 mkdir($mfptr->{mf_dir}/${hname}$i) failed -- $!\n";
            return 1;
        }
    }

    # Each worker is to ensure that the length of the directory plus
    # file does not exceed the OS's limit.  Otherwise, reset the
    # value for the mf_vertical.

    $vname = 'dmf';

    $vertical = $mfptr->{mf_vertical};
    $dirname  = "$mfptr->{mf_dir}/${hname}${dirend}";

    for ( $i = 0 ; $i < $vertical ; $i++ ) {

        # Need to conform to NBU's restriction.  Maximum path for
        # a file is 1000 bytes (for Advanced Clent) and 1023 for
        # Regular file.  Pick 1000 as the limit.
        # At the OS level, Linux has 4096 as the maximum path length
        # and other three OSes (Solaris, AIX and HP-UX) has 1024.
        #
        # AIX appears to be most restrictive on the total length
        # for a file as the OS only allows 255 bytes.
        #
        # 980 (directory path) + 20 (file name) == 1000 bytes
        if ( length("$dirname/${vname}$i") <= 980 ) {
            $dirname .= "/${vname}$i";
        }
        else {
            if ( $i != ( $vertical - 1 ) ) {
                $mfptr->{mf_vertical} = $vertical = $i;
                if ( $mfptr->{mf_verbose} ) {
                    print STDOUT
                      "Reduce Vertical directory to $mfptr->{mf_vertical}\n";
                }
            }
            last;
        }
    }

    $start = $mfptr->{mf_worker_task}[$worker]{mf_start};
    $end   = $mfptr->{mf_worker_task}[$worker]{mf_end};

    $pname = $mfptr->{mf_prefix};

    for ( $i = $start ; $i < $end ; $i++ ) {

        # Find the horizontal directory this file will be created in.
        $hdir = $dirstart + ( int( rand() * $numofdir ) % $numofdir );

        # Find the vertical directory this file will be created in.
        $vdir = int( rand() * $vertical ) % $vertical;

        $dirname = "$mfptr->{mf_dir}/${hname}${hdir}";
        for ( $j = 0 ; $j < $vdir ; $j++ ) {
            $dirname .= "/${vname}$j";
        }

        # Make sure the entire directory exist.
        if ( !-d $dirname ) {
            $mkdir_rc = system("mkdir -p $dirname");
            if ( $mkdir_rc != 0 ) {
                print STDERR
                  "rmf:2 mkdir(${dirname}) failed -- $mkdir_rc -- $!\n";
                return 1;
            }
        }

        # Recompute the mf_fsize if mf_rand_fsize is ON ???
        $fsize = $mfptr->{mf_fsize};

        if (
            !$mfptr->{mf_create_file}( "${dirname}/${pname}_${worker}_$i",
                $fsize ) )
        {
            print STDERR "rmf:3 Worker $worker open($i) failed\n";
            return 1;
        }
    }

    return 0;
}

sub dpp_oqs_worker($;$) {
    my ( $mfptr, $worker ) = @_;

    my ( $i, $start, $end );
    my ( $fsize, $diri, $numofdir, $pname, $fname, $ftype );
    my ( $entries, $remainder, $dirstart, $dirend, $oqs );
    my ($dirname);

    $entries   = int( $mfptr->{mf_horizontal} / $mfptr->{mf_workers} );
    $remainder = int( $mfptr->{mf_horizontal} % $mfptr->{mf_workers} );

    # The starting and ending directories for this worker.
    $dirstart = $worker * $entries;
    $dirend   = $entries + $dirstart;

    if ( $worker == ( $mfptr->{mf_workers} - 1 ) ) {

        # The last worker has to do more -- remaining slots
        $dirend += $remainder;
    }

    $numofdir = $dirend - $dirstart;

    $pname = $mfptr->{mf_prefix};

    # Create the horizontal directories.
    for ( $i = $dirstart ; $i < $dirend ; $i++ ) {

        if ( !mkdir("$mfptr->{mf_dir}/${pname}$i") ) {
            print STDERR
              "oqs:1 mkdir($mfptr->{mf_dir}/${pname}$i) failed -- $!\n";
            return 1;
        }
    }

    $start = $mfptr->{mf_worker_task}[$worker]{mf_start};
    $end   = $mfptr->{mf_worker_task}[$worker]{mf_end};

    for ( $i = $start ; $i < $end ; $i++ ) {

        # Recompute the mf_fsize if mf_rand_fsize is ON ???
        $fsize = $mfptr->{mf_fsize};

        # Find the directory this file will be created in.
        $diri = $dirstart + ( int( rand() * $numofdir ) % $numofdir );

        $ftype = int( rand() * $i ) % 3;

        $dirname = "$mfptr->{mf_dir}/${pname}${diri}";
        if ( $ftype == 0 ) {
            $fname = "$dirname/odm_${worker}_$i";
            if ( !dpp_mf_create_odm( $fname, $fsize, $mfptr->{mf_header} ) ) {
                print STDERR "oqs:2 Worker $worker open($i) failed\n";
                return 1;
            }
        }
        elsif ( $ftype == 1 ) {
            $fname = "$dirname/qio_${worker}_$i";
            if ( !dpp_mf_create_qio( $fname, $fsize, $mfptr->{mf_header} ) ) {
                print STDERR "oqs:3 Worker $worker open($i) failed\n";
                return 1;
            }
        }
        elsif ( $ftype == 2 ) {
            $fname = "$dirname/setext_${worker}_$i";
            if ( !dpp_mf_create_setext( $fname, $fsize ) ) {
                print STDERR "oqs:4 Worker $worker open($i) failed\n";
                return 1;
            }
        }
    }

    return 0;
}

sub dpp_new_worker($;$) {
    my ( $mfptr, $worker_slot ) = @_;

    my ( $pid, $child_rc, $tried, $attempts );

    $child_rc = $tried = 0;

    # Try 5 minutes if fork() is returning EAGAIN repeatedly.
    $attempts = 60;

  FORK: {
        $pid = fork();
        if ($pid) {

            # Parent section of the code.
            # Child's process ID is available in pid variable

            # Tell the caller (parent's thread) a process has
            # been created.
            return $pid;
        }
        elsif ( defined($pid) && $pid == 0 ) {

            # pid is zero here if defined.
            # So, this is the child's section of the code.
            # The parent's pid can be gotten by calling getppid().

            # Set the Child's exit code to 0 (assume everything
            # will be OK).
            $child_rc = $mfptr->{mf_worker_func}( $mfptr, $worker_slot );
        }
        elsif ( $! == EAGAIN && $tried++ < $attempts ) {

            # The system is lacking some sort of resource and
            # prevented a successful fork(), sleep for 5 seconds
            # and try again.
            sleep(5);
            redo FORK;
        }
        else {

            # Strange error
            return -1;
        }
    }

    exit($child_rc);
}

sub dpp_mf_create_workers($) {
    my ($mfptr) = @_;

    my ($i);
    my ( $entries,   $remainder );
    my ( $worker_rc, $workers_exited );

    $entries   = int( $mfptr->{mf_files} / $mfptr->{mf_workers} );
    $remainder = int( $mfptr->{mf_files} % $mfptr->{mf_workers} );

    for ( $i = 0 ; $i < $mfptr->{mf_workers} ; $i++ ) {

        # The starting and ending slots for this worker.
        $mfptr->{mf_worker_task}[$i]{mf_start} = $i * $entries;
        $mfptr->{mf_worker_task}[$i]{mf_end} =
          $entries + $mfptr->{mf_worker_task}[$i]{mf_start};

        if ( $i == ( $mfptr->{mf_workers} - 1 ) ) {

            # The last worker has to do more -- remaining slots
            $mfptr->{mf_worker_task}[$i]{mf_end} += $remainder;
        }

        # Last worker has to do a bit extra.
        $worker_rc = dpp_new_worker( $mfptr, $i );
        if ( $worker_rc < 0 ) {
            print STDERR "dpp_new_worker returns $worker_rc\n";
            exit($worker_rc);
        }

        # Store the child's pid
        $mfptr->{mf_worker_task}[$i]{worker_pid} = $worker_rc;
    }

    # wait for all the workers to terminate
    do {
        sleep(1);
        $workers_exited = waitpid( -1, &WNOHANG );
    } until $workers_exited == -1;

    return 1;
}

# Create mf_files files of size mf_fsize each in the mf_dir directory.
# /<mnt-point>/mf/mf_<pid's slot>_0 ... /<mnt-point>/mf/mf_<pid's slot>_<N-1>
sub dpp_dir_with_mf($) {
    my ($mfptr) = @_;

    my ($i);

    # This rotuine is using the generic worker dpp_mf_worker()
    $mfptr->{mf_worker_func} = \&dpp_mf_worker;

    $mfptr->{mf_prefix} = 'mf';
    $mfptr->{mf_dir} .= "/$mfptr->{mf_prefix}";

    if ( !-d "$mfptr->{mf_dir}" ) {
        if ( !mkdir("$mfptr->{mf_dir}") ) {
            print STDERR "mf:1 mkdir($mfptr->{mf_dir}) failed -- $!\n";
            return -1;
        }
    }

    if ( !dpp_mf_create_workers($mfptr) ) {
        print STDERR "mf:2 dpp_mf_create_workers erred\n";
        return -1;
    }

    return 0;
}

# A directory that has mf_horizontal sub-directories with mf_files files
# distributed among these sub-directories.
# /<om_mnt>/bmf/bmf0/<file0> ... /<om_mnt>/bmf<N-1>/<file<N-1>>
sub dpp_breath_with_mf($) {
    my ($mfptr) = @_;

    my ($i);

    $mfptr->{mf_worker_func} = \&dpp_bmf_worker;

    $mfptr->{mf_prefix} = 'bmf';
    $mfptr->{mf_dir} .= "/$mfptr->{mf_prefix}";

    if ( !-d "$mfptr->{mf_dir}" ) {
        if ( !mkdir("$mfptr->{mf_dir}") ) {
            print STDERR "breath:1 mkdir($mfptr->{mf_dir}) failed -- $!\n";
            return -1;
        }
    }

    if ( !dpp_mf_create_workers($mfptr) ) {
        print STDERR "breath:2 dpp_mf_create_workers erred\n";
        return -1;
    }

    return 0;
}

# NetBackup has a restriction on the maximum path length -- it is
# 1023 bytes for a regular file and 1000 for server free agent.
# So, depending on the length of each directory, the depth can vary.
#
# /<om_mnt>/dwf/dmf0/dmf1/.../dmf1023
sub dpp_depth_with_mf($) {
    my ($mfptr) = @_;

    my ( $i, $vertdirs );
    my ($mkdir_rc);

    $mfptr->{mf_worker_func} = \&dpp_dmf_worker;

    $mfptr->{mf_prefix} = 'dmf';
    $mfptr->{mf_dir} .= "/$mfptr->{mf_prefix}";

    if ( !-d "$mfptr->{mf_dir}" ) {
        if ( !mkdir("$mfptr->{mf_dir}") ) {
            print STDERR "depth:1 mkdir($mfptr->{mf_dir}) failed -- $!\n";
            return -1;
        }
    }

    # Create the vertical directories and possibly adjust the value
    # in mfptr->{mf_vertical}.
    $vertdirs = $mfptr->{mf_dir};
    for ( $i = 0 ; $i < $mfptr->{mf_vertical} ; $i++ ) {

        # Need to conform to NBU's restriction.  Maximum path for
        # a file is 1000 bytes (for Advanced Clent) and 1023 for
        # Regular file.  Pick 1000 as the limit.
        # At the OS level, Linux has 4096 as the maximum path length
        # and other three OSes (Solaris, AIX and HP-UX) has 1024.
        #
        # AIX appears to be most restrictive on the total length
        # for a file as the OS only allows 255 bytes.
        #
        # 980 (directory path) + 20 (file name) == 1000 bytes
        if ( length("$vertdirs/$mfptr->{mf_prefix}$i") <= 980 ) {
            $vertdirs .= "/$mfptr->{mf_prefix}$i";
        }
        else {
            if ( $i != ( $mfptr->{mf_vertical} - 1 ) ) {

                # Reduce the number in mf_vertical to the
                # actual number of directories being created.
                $mfptr->{mf_vertical} = $i;
                if ( $mfptr->{mf_verbose} ) {
                    print STDOUT
                      "Reduce Vertical directory to $mfptr->{mf_vertical}\n";
                }
                last;
            }
        }
    }

    $mkdir_rc = system("mkdir -p $vertdirs");
    if ( $mkdir_rc != 0 ) {
        print STDERR "depth:2 mkdir(${vertdirs}) failed -- $mkdir_rc -- $!\n";
        return -1;
    }

    if ( !dpp_mf_create_workers($mfptr) ) {
        print STDERR "depth:3 dpp_mf_create_workers erred\n";
        return -1;
    }

    return 0;
}

# A directory with random number of depth and breath of many files.
# /<om_mnt>/rmf
sub dpp_random_with_mf($) {
    my ($mfptr) = @_;

    my ($i);

    $mfptr->{mf_worker_func} = \&dpp_rmf_worker;

    $mfptr->{mf_prefix} = 'rmf';
    $mfptr->{mf_dir} .= "/$mfptr->{mf_prefix}";

    if ( !-d "$mfptr->{mf_dir}" ) {
        if ( !mkdir("$mfptr->{mf_dir}") ) {
            print STDERR "random:1 mkdir($mfptr->{mf_dir}) failed -- $!\n";
            return -1;
        }
    }

    if ( !dpp_mf_create_workers($mfptr) ) {
        print STDERR "random:2 dpp_mf_create_workers erred\n";
        return -1;
    }

    return 0;
}

# A directory with mixture of odm (o), qio (q), and setext (s) files.
# /<om_mnt>/oqs/oqs0 /<om_mnt>/oqs/oqs1 ... /<om_mnt>/oqs/oqs<N-1>
#
# NOTES:
# 1. Seem not able to create more than 32764 directories in a directory.
sub dpp_oqs_with_mf($) {
    my ($mfptr) = @_;

    my ($i);

    $mfptr->{mf_worker_func} = \&dpp_oqs_worker;

    $mfptr->{mf_prefix} = 'oqs';
    $mfptr->{mf_dir} .= "/$mfptr->{mf_prefix}";

    if ( !-d "$mfptr->{mf_dir}" ) {
        if ( !mkdir("$mfptr->{mf_dir}") ) {
            print STDERR
              "dpp_oqs_with_mf:1 mkdir($mfptr->{mf_dir}) failed -- $!\n";
            return -1;
        }
    }

    if ( !dpp_mf_create_workers($mfptr) ) {
        print STDERR "dpp_oqs_with_mf:2 dpp_mf_create_workers erred\n";
        return -1;
    }

    return 0;
}

############################ Main Starts Here ############################

$getoptret = getopts( 'd:w:n:s:B:D:RH:TL:vh', \%opts );
if ( $getoptret eq '' ) {
    dpp_mf_usage();

    # NOTREACHED
}

$mf_args{mf_verbose} = $opts{v} ? 1 : 0;

if ( $opts{h} ) {
    dpp_mf_usage( $opts{h} );

    # NOTREACHED
}

$mf_args{mf_dir} = $opts{d} ? $opts{d} : undef;
if ( !defined( $mf_args{mf_dir} ) || !-d $mf_args{mf_dir} ) {
    print STDERR "Need to speicify a directory (-d $mf_args{mf_dir}) "
      . "that exist!\n";
    exit(2);
}

if ( exists( $ENV{DPP_MF_WORKERS} ) ) {
    $mf_args{mf_workers} = $ENV{DPP_MF_WORKERS};
}
else {
    $mf_args{mf_workers} = $opts{w} ? $opts{w} : 2;
}

$mf_args{mf_files} = $opts{n} ? $opts{n} : 1e6;

$mf_args{mf_fsize}      = $opts{s} ? $opts{s} : 1024;
$mf_args{mf_rand_fsize} = $opts{R} ? 1        : 0;

# The unit for -H is in Kbytes.
$mf_args{mf_header} = $opts{H} ? $opts{H} : 2;
$mf_args{mf_setext} = $opts{T} ? 1        : 0;

$mf_args{mf_horizontal} = $opts{B} ? $opts{B} : 1024;

# 158 is picked after experimenting using the naming convention used here.
$mf_args{mf_vertical} = $opts{D} ? $opts{D} : 158;

$which_mf = $opts{L} ? $opts{L} : 'M';
if ( $which_mf eq 'M' ) {

    # -M calls dpp_dir_with_mf()
    $mf_funcname = 'dpp_dir_with_mf';
}
elsif ( $which_mf eq 'B' ) {

    # -B calls dpp_breath_with_mf()
    $mf_funcname = 'dpp_breath_with_mf';
}
elsif ( $which_mf eq 'D' ) {

    # -D calls dpp_depth_with_mf()
    $mf_funcname = 'dpp_depth_with_mf';
}
elsif ( $which_mf eq 'R' ) {

    # -R calls dpp_random_with_mf()
    $mf_funcname = 'dpp_random_with_mf';
}
elsif ( $which_mf eq 'O' ) {

    # -O calls dpp_qio_odm_with_mf()
    $mf_funcname = 'dpp_oqs_with_mf';

    # -L O uses setext(1), qiomkfile(1) and odmmkfile(1)
    $mf_args{mf_setext} = 1;
}
else {
    dpp_mf_usage();

    # NOTREACHED
}

if ( $mf_args{mf_setext} ) {

    # Verify the mf_fsize is in multiple of 1024 bytes.
    if ( ( $mf_args{mf_fsize} % 1024 ) != 0 ) {
        print STDERR "-s $mf_args{mf_fsize} is not in 1024 multiple\n";
        dpp_mf_usage();

        # NOTREACHED
    }

    # The setext(1M) command used Kbytes as size unit.
    $mf_args{mf_fsize} = int( $mf_args{mf_fsize} / 1024 );

    $mf_args{mf_create_file} = \&dpp_mf_create_setext;
}
else {
    $mf_args{mf_create_file} = \&dpp_mf_create_ascii;
}

$mf_args{mf_func_to_call} = \&$mf_funcname;

if ( $mf_args{mf_verbose} ) {
    print "Start --->>> " . scalar localtime() . "\n";
}

$mf_retcode = $mf_args{mf_func_to_call}->( \%mf_args );

if ( $mf_args{mf_verbose} ) {
    print "End   --->>> " . scalar localtime() . "\n";
}

if ( $mf_args{mf_verbose} ) {
    print "mf_dir $mf_args{mf_dir}\n";
    print "mf_workers $mf_args{mf_workers}\n";
    print "mf_files $mf_args{mf_files}\n";
    print "mf_fsize $mf_args{mf_fsize}\n";
    print "mf_rand_fsize $mf_args{mf_rand_fsize}\n";
    print "mf_header $mf_args{mf_header}\n";
    print "mf_setext $mf_args{mf_setext}\n";
    print "which_mf $which_mf $mf_funcname\n";
}

exit($mf_retcode);
