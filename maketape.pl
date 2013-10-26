#!/usr/bin/perl
# title:        maketape.pl
# author:       drew jess (iamdrew@gmail.com)
# description:  generate random tapes
#                 - read in all mp3s from dir
#                 - find random mp3, 
#                   - get length
#                   - add to playlist if enough room
#                   - update 'time remaining'
#                 - repeat ad nauseum      
#                 - print out a pretty playlist

# modules #########################################################################################

use strict;
use warnings;

use File::Find;
use MP3::Info;
use MP3::Tag;
use Data::Dumper;
use Getopt::Std;
use File::Basename;

# variables #######################################################################################

# lists and hashes to keep mp3 info in 
my @mp3s;
my $total_mp3s;
my %length_of;
my %info_of;

# various variables
my $script_name    = basename($0);

# display preferences for formatting.  make these dynamic TODO
my $track_no_width = 5;
my $artist_width   = 50;
my $song_width     = 50;
my $length_width   = 6;

# basedir to search for mp3s in.  provide this as an option TODO
my $mp3dir               = '/mnt/sharefs/music/iTunes/Music';

# the below values are in seconds.  allow overwrite with opts TODO
my $current_side         = '1'
my $sides                = '1';
my $minimum_track_length = '90';    
my $maximum_track_length = '420';   
my $tape_length          = '4200';  
my $end_buffer           = '60';    # don't look for more songs if we only have X seconds left

# command line options
our $opt_b;     # end buffer ("buffer")
our $opt_d;     # mp3 directory ("dir")
our $opt_h;     # usage ("help")
our $opt_l;     # mix-length to create ("length")
our $opt_m;     # maximum track length ("max")
our $opt_s;     # sides to to create.  ("sides")
our $opt_u;     # minimum track length ("minim-u-m")

# usage ###########################################################################################

my $usage = qq{
--------------------------------------------
$script_name: a script for creating mixtapes
--------------------------------------------

OPTIONS:  -b: end-buffer.  space you're happy to leave at the end of the tape. 
              the smaller that this is, the harder it is to get it spot on. 
              we'll try our hardest though.
          -d: directory that you want the script to look for mp3s in.
          -l: length of tape to create.  defaults to 70 minutes. (4200 seconds)
          -m: maximum track size to use.  (default value: 420 seconds)
          -u: mimumum track size to use.  (default value: 90 seconds)
          -s: number of sides for the tape
          -h: print usage information and exists

          where it makes sense, you can provide times to these options in either 
          seconds or minutes.  4200 would be parsed as seconds.  4200m would be 
          parsed as minutes.  no plans for hours, days, weeks or years yet.

EXAMPLES: 
          ./$script_name                  use defaults
          ./$script_name -l 120m          make tape length 120 minutes
          ./$script_name -l 4200          make tape length 4200 seconds
          ./$script_name -m 10m -u 5m     max track length 10m, min track length 5m
};

# getopts ########################################################################################

getopts('b:d:hl:m:s:u:');

# parse help
if ($opt_h) {
  print $usage;
  exit 0;
}

# parse mp3 directory
if ($opt_d) {
  if (-d $opt_d) {
    $mp3dir = $opt_d;
  } else {
    print "directory provided with -d option is not a valid target\n";
    exit 1;
  }
}

# parse tape length
if ($opt_l) {
  if ($opt_l =~ /^-?\d+$/) {
    # we've been given an int; treat as seconds
    $tape_length = $opt_l;
    print "user-specified tape length: $tape_length seconds\n";
  } elsif ($opt_l =~ /^[1-9][0-9]*[mM]$/) {
    # we've been given a 'minutes' value; convert
    $opt_l =~ s/[mM]//s;
    $tape_length = min2sec($opt_l);
    print "user-specified tape length: $tape_length seconds\n";
  } else {
    print "argument provided to option -l is not a valid length\n";
    print "please provide in seconds (-l 4200) or minutes (-l 70m)\n";
    exit 1;
  }
}

# parse maximum track length
if ($opt_m) {
  if ($opt_m =~ /^-?\d+$/) {
    # we've been given an int; treat as seconds
    $maximum_track_length = $opt_m;
    print "user-specified maximum track length: $maximum_track_length seconds\n";
  } elsif ($opt_m =~ /^[1-9][0-9]*[mM]$/) {
    # we've been given a 'minutes' value; convert
    $opt_m =~ s/[mM]//s;
    $maximum_track_length = min2sec($opt_m);
    print "user-specified maximum track length: $maximum_track_length seconds\n";
  } else {
    print "argument provided to option -m is not a valid length\n";
    print "please provide in seconds (-m 90) or minutes (-m 2m)\n";
    exit 1;
  }
}

# parse minimum track length
if ($opt_u) {
  if ($opt_u =~ /^-?\d+$/) {
    # we've been given an int; treat as seconds
    $minimum_track_length = $opt_u;
    print "user-specified minimum track length: $minimum_track_length seconds\n";
  } elsif ($opt_u =~ /^[1-9][0-9]*[mM]$/) {
    # we've been given a 'minutes' value; convert
    $opt_u =~ s/[mM]//s;
    $minimum_track_length = min2sec($opt_u);
    print "user-specified minimum track length: $minimum_track_length seconds\n";
  } else {
    print "argument provided to option -u is not a valid length\n";
    print "please provide in seconds (-u 90) or minutes (-u 2m)\n";
    exit 1;
  }
}

# parse sides 
if ($opt_s) {
  if ($opt_s =~ /^-?\d+$/) {
    $sides = $opt_s;
    print "user-specified number of sides: $sides\n;"
  } else {
    print "argument provided to option -s is not a valid integer\n";
    exit 1;
  }
}


# subroutines #####################################################################################

sub get_mp3s {

  # description: recursively finds mp3s in $basedir and pushes 
  #              fully qualified path onto array ref provided
  # $_[0]:       directory in which to search through
  # $_[1]:       reference of list in which to push results

  my $basedir  = shift;
  my $mp3s_ref = shift;

  opendir (DIR, $basedir) or die "Unable to open $basedir: $!";

  my @files = grep { !/^\.{1,2}$/ } readdir (DIR);  # forget about . and ..  
  @files = map { $basedir . '/' . $_ } @files;      # make sure found files are fully qualified
                                                    # we'll tack on the full path with map()
  foreach my $file (@files) {
    if (-d $file) {

      # recurse through any other directories we find
      get_mp3s($file,$mp3s_ref);

    } elsif ($file =~ /.*\.mp3$/) {

      # only add to our list if it's an mp3
      push(@$mp3s_ref,$file); 

    } 
  }
}

sub random_mp3 { 

  # description:  returns a random element from the provided array
  # $_[0]:        reference of list which contains mp3 filepaths
  
  my $mp3s_ref   = shift; 
  my $no_of_mp3s = @$mp3s_ref;

  # choose a random element from the @mp3s list.
  my $random_mp3 = ${ $mp3s_ref }[int(rand($no_of_mp3s + 1))];

  return $random_mp3; 

} 

sub get_length {

  # description:  retrieves the length of the provided mp3.
  #               adds a 'length' key to %info_of{$target}.
  # $_[0]:        mp3 to check length of
  # $_[1]:        hash reference of %info_of
  # returns:      length of track in secs 

  my $target        = shift;
  my $info_ref      = shift;

  # let's get the length in seconds.  MP3::Info is very precise
  # and gives us fractions of a second.  we pretty much always
  # want to round up though.  so let's do that.

  my $mp3           = MP3::Info->new($target);
  my $mp3_length    = $mp3->secs();
     $mp3_length    = int($mp3_length + 1);    

  # let's add $mp3_length to our %info_of hash for this track
  $info_ref->{$target}{'length'} = $mp3_length;

  # return length of track in full seconds
  return int($mp3_length);
}

sub get_tags {

  # description:  get most popular id3 tags for a provided mp3
  # $_[0]:        full path of an mp3 file
  # returns:      hashref populated id3 info

  my $target      = shift;

  my $id3         = MP3::Tag->new($target);  
  my $id3_info    = $id3->autoinfo();

  return $id3_info;

}

sub min2sec {

  # description:  convert minutes to seconds
  # $_[0]:        minutes as an integer
  # returns:      seconds as an integer

  my $mins = shift;
  my $secs = $mins * 60;
  return $secs;

}

# main ############################################################################################

# search for all mp3 files located in $mp3dir
get_mp3s($mp3dir,\@mp3s);
$total_mp3s = scalar(@mp3s);

# get these values back to defaults
my $track_number   = 1;   # incremented after each selection 
my $total_length   = 0;   # total length of finished tape
my $attempts       = 0;   
my $attempts_limit = 500; # give up fitting more songs on after

# print header for our output.  can we make this code prettier? TODO
printf ("%-${track_no_width}s%-${artist_width}s%-${song_width}s%-${length_width}s\n","#","ARTIST","SONG","(m:ss)");

# now let's keep finding tracks until we've run out of space or have tried too hard
until ($tape_length < $end_buffer || $attempts > $attempts_limit) {

  # choose a random track
  my $choice = random_mp3(\@mp3s);

  # get its id3 tags and length in seconds
  $info_of{$choice} = get_tags($choice);
  my $choice_length = get_length($choice,\%info_of);  

  if ( $choice_length > $tape_length          ||  
       $choice_length > $maximum_track_length ||   
       $choice_length < $minimum_track_length ) {
    
    # skip this track
    $attempts++;
    next;
  }

  # calculate useful times for track to be displayed and pull out artist / song info 
  my $choice_mins = int($choice_length / 60);
  my $choice_secs = sprintf("%02d",$choice_length % 60);
  my $artist = $info_of{$choice}{'artist'};
  my $song  = $info_of{$choice}{'song'};

  if (!$song || !$artist) {
    # we don't want tracks with no id3 tags
    next;
  } 

  # print song details to screen.  can we make this code prettier? TODO
  printf ("%-${track_no_width}s%-${artist_width}s%-${song_width}s%-${length_width}s\n","$track_number","$artist","$song","($choice_mins:$choice_secs)");

  # let's update some stuff for the next iteration
  $tape_length = $tape_length - $choice_length;
  $total_length = $total_length + $choice_length;
  $track_number++;
}

# let's calculate the grand total length of our generated tape
my $total_mins = int($total_length / 60);
my $total_secs = sprintf("%02d",$total_length % 60);

print "TOTAL: $total_mins:$total_secs\n";

# print Dumper(\%info_of);
