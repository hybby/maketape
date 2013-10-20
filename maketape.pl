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

# modules ####################################################

use strict;
use warnings;

use Time::Piece;
use Time::Seconds;
use File::Find;
use MP3::Info;
use MP3::Tag;
use Data::Dumper;

# variables ##################################################



my @mp3s;
my $total_mp3s;
my %length_of;
my %info_of;

my @playlist;

# default preferences - can be overwritten on cmd line
my $mp3dir     = '/mnt/sharefs/music/iTunes/Music';
my $tape_length = '4200';       # length in seconds

my $minimum_track_length = '90';   # 1 min 30 sec
my $maximum_track_length = '420';  # 6 min

# subroutines ################################################

sub get_mp3s {

  # description: recursively finds mp3s in $basedir and pushes 
  # the fully qualified path onto the array reference provided
  # $_[0]: directory in which to search through
  # $_[1]: reference of list in which to push results

  my $basedir  = shift;
  my $mp3s_ref = shift;

  opendir (DIR, $basedir) or die "Unable to open $basedir: $!";

  my @files = grep { !/^\.{1,2}$/ } readdir (DIR);  # forget about . and ..  
  @files = map { $basedir . '/' . $_ } @files;    # make sure found files are fully qualified
              # we'll tack on the full path with map()
  foreach my $file (@files) {
    if (-d $file) {
      get_mp3s($file,$mp3s_ref);
    } elsif ($file =~ /.*\.mp3$/) {
      push(@$mp3s_ref,$file); 
    } 
  }
}

sub random_mp3 { 

  # description:  returns a random element from the provided array
  # $_[0]: reference of list which contains mp3s
  
  my $mp3s_ref   = shift; 
  my $no_of_mp3s = @$mp3s_ref;

  # choose a random element from the @mp3s list.
  my $random_mp3 = ${ $mp3s_ref }[int(rand($no_of_mp3s + 1))];

  return $random_mp3; 

} 

sub get_length {

  # description:  retrieves the length of the provided mp3.
  # adds a 'length' key to %info_of{$target}.
  # $_[0]: mp3 to check length of
  # $_[1]: hash reference of %info_of
  # returns: length of track in secs 

  my $target        = shift;
  my $info_ref      = shift;
  my $mp3len_dt     = undef;

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
  # $_[0]: full path of an mp3 file
  # returns: a hashref populated with popular id3 tags

  my $target      = shift;

  my $id3         = MP3::Tag->new($target);  
  my $id3_info    = $id3->autoinfo();

  return $id3_info;

}

# main #######################################################

# let's get all mp3s
get_mp3s($mp3dir,\@mp3s);
$total_mp3s = scalar(@mp3s);

my $track_number = 1;
my $total_length = 0;

# we'll give up trying to assign new tracks after $attempts_limit
my $attempts       = 0;      
my $attempts_limit = 500;

# formatting settings
my $track_no_width = 3;
my $artist_width   = 50;
my $song_width     = 50;
my $length_width   = 6;


# header
printf ("%-${track_no_width}s%-${artist_width}s%-${song_width}s%-${length_width}s\n","#","ARTIST","SONG","(m:ss)");

until ($tape_length < 30 || $attempts > $attempts_limit) {

  # choose a random track
  my $choice = random_mp3(\@mp3s);

  # get its tags and length
  $info_of{$choice} = get_tags($choice);
  my $choice_length = get_length($choice,\%info_of);  

  if ( $choice_length > $tape_length          ||  
       $choice_length > $maximum_track_length ||   
       $choice_length < $minimum_track_length ) {
    
    # skip this track
    $attempts++;
    next;
  }

  my $choice_mins = int($choice_length / 60);
  my $choice_secs = sprintf("%02d",$choice_length % 60);
  my $artist = $info_of{$choice}{'artist'};
  my $song  = $info_of{$choice}{'song'};

  if (!$song || !$artist) {
    # we don't want tracks with no id3 tags
    next;
  } 

  printf ("%-${track_no_width}s%-${artist_width}s%-${song_width}s%-${length_width}s\n","$track_number","$artist","$song","($choice_mins:$choice_secs)");
  # print "$track_number\t$artist - $song\t($choice_mins:$choice_secs)\n";
  $tape_length = $tape_length - $choice_length;
  $total_length = $total_length + $choice_length;
  $track_number++;
}

my $total_mins = int($total_length / 60);
my $total_secs = sprintf("%02d",$total_length % 60);

print "TOTAL: $total_mins:$total_secs\n";

# print Dumper(\%info_of);
