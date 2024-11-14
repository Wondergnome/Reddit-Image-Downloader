#!/usr/bin/perl
use strict;
use warnings;
use LWP::UserAgent;
use JSON;
use File::Basename;
use File::Path qw(make_path remove_tree);
use Digest::MD5 qw(md5_hex);
use POSIX qw(strftime);
use URI;
use Storable qw(retrieve store);
use Term::ANSIColor;

# Function to download images
sub download_images {
    my ($download_url, $dir, $num) = @_;
    my $count = 0;
    my $non_image_count = 0;
    my $pdownloaded = 0;
    my %hashes;
    my $ua = LWP::UserAgent->new(agent => 'Mozilla/5.0');

    # Check if subreddit/user exists before downloading
    print color('bold green');
    print "Checking existence of subreddit/user: $download_url\n";
    print color('reset');
    my $response = $ua->get($download_url);
    unless ($response->is_success) {
        warn color('bold red');
        print "Error: Subreddit or user not found at $download_url (", $response->status_line, ")\n";
        print color('reset');
        return; # Exit function if subreddit/user is not found
    }

    # Create the directory only if the subreddit/user exists
    make_path($dir);

    while ($download_url && $count < $num) {
        print color('bold green');
        print "Fetching data from URL: $download_url\n";
        print color('reset');
        my $response = $ua->get($download_url);
        unless ($response->is_success) {
            warn color('bold red');
            print "Could not get data from $download_url: ", $response->status_line, "\n";
            print color('reset');
            last;
        }
        my $json_data = $response->decoded_content;
        my $data = eval { decode_json($json_data) };
        if ($@) {
            warn color('bold red');
            print "Could not decode JSON data: $@\n";
            print color('reset');
            last;
        }

        foreach my $post (@{$data->{'data'}->{'children'}}) {
            my $url = $post->{'data'}->{'url'};
            my $author = $post->{'data'}->{'author'};
            my $created_utc = $post->{'data'}->{'created_utc'};
            my $date = strftime("%d-%m-%Y", gmtime($created_utc));

            next unless defined $url && $url =~ /\.(jpe?g|png|gif)$/i;
            next unless defined $author;

            my $is_external = ($url !~ /^https?:\/\/(i\.)?redd\.it\//);

            my $filename = basename($url);
            $filename = "$date-$author-$filename";
            $filename = "external-$filename" if $is_external;

            # Strip 'u/' or 'r/' prefix from $dir
            $dir =~ s/^u\///;
            $dir =~ s/^r\///;

            my $path = "$dir/$filename";

            if (-e $path) {
                $pdownloaded++;
                next;
            }

            my $content = $ua->get($url)->decoded_content;
            next unless defined $content;

            my $hash = md5_hex($content);
            next if exists $hashes{$hash};

            open my $fh, '>', $path or die "Could not open $path: $!\n";
            binmode $fh;
            print $fh $content;
            close $fh;

            $hashes{$hash} = 1;
            print color('bold cyan');
            print "Downloaded image: $url\n";
            print color('reset');

            $count++;
            last if $count >= $num;
        }

        last unless $data->{'data'}->{'after'};
        $download_url = "$download_url&after=" . $data->{'data'}->{'after'};
    }

    unless (-e "$dir/.forcegallery") {
        open my $force_fh, '>', "$dir/.forcegallery" or die "Could not create .forcegallery file: $!\n";
        close $force_fh;
    }
    print color('bold green');
    print "Done. Downloaded $count images to $dir.\n";
    print "Skipped $non_image_count non-image URLs.\n";
    print "$pdownloaded images were ignored because they already exist.\n";
    print color('reset');
}

## Function to delete a reference from history and remove folder
sub delete_reference {
    my ($history) = @_;
    my @keys = keys %$history;

    if (@keys == 0) {
        print color('bold yellow');
        print "No references to delete.\n";
        print color('reset');
        return;
    }

    print "Select a reference to delete ('back' to go back):\n";
    for my $i (0 .. $#keys) {
        print "$i. $keys[$i]\n";
    }
    print "Enter your choice: ";
    my $choice = <STDIN>;
    chomp $choice;
    return if $choice eq 'back';

    if (defined $keys[$choice]) {
        my $key = $keys[$choice];
        delete $history->{$key};

        my $dir;
        if ($key =~ m{^u/(.+)$}) {
            $dir = "downloads/user_images/$1";  # Strip 'u/' prefix
        } elsif ($key =~ m{^r/(.+)$}) {
            $dir = "downloads/subreddit_images/$1";  # Strip 'r/' prefix
        }

        if ($dir && -d $dir) {
            print "Are you sure you want to delete the folder '$dir' and all its contents? (yes/no): ";
            my $confirm = <STDIN>;
            chomp $confirm;
            if (lc $confirm eq 'yes') {
                remove_tree($dir);
                print color('bold green');
                print "Deleted reference and folder for $key.\n";
                print color('reset');
            } else {
                print color('bold yellow');
                print "Folder deletion canceled.\n";
                print color('reset');
            }
        } else {
            print color('bold yellow');
            print "Directory $dir does not exist.\n";
            print color('reset');
        }
    } else {
        print color('bold red');
        print "Invalid choice.\n";
        print color('reset');
    }
}

# Function to search for subreddits a user has posted to
sub search_subreddits {
    my ($username) = @_;
    my $ua = LWP::UserAgent->new(agent => 'Mozilla/5.0');
    my $url = "https://www.reddit.com/user/$username/submitted/.json?limit=100";
    my %subreddits;

    while ($url) {
        print color('bold green');
        print "Fetching data from URL: $url\n";
        print color('reset');
        my $response = $ua->get($url);
        unless ($response->is_success) {
            warn color('bold red');
            print "Could not get data from $url: ", $response->status_line, "\n";
            print color('reset');
            last;
        }
        my $json_data = $response->decoded_content;
        my $data = eval { decode_json($json_data) };
        if ($@) {
            warn color('bold red');
            print "Could not decode JSON data: $@\n";
            print color('reset');
            last;
        }

        foreach my $post (@{$data->{'data'}->{'children'}}) {
            my $subreddit = $post->{'data'}->{'subreddit'};
            $subreddits{$subreddit} = 1 if defined $subreddit;
        }

        last unless $data->{'data'}->{'after'};
        $url = "https://www.reddit.com/user/$username/submitted/.json?limit=100&after=" . $data->{'data'}->{'after'};
    }

    return keys %subreddits;
}

# Main program
my $log_file = 'download_log.dat';
my $history = -e $log_file ? retrieve($log_file) : {};

MENU: while (1) {
    print color('bold magenta');
    print "Select an option:\n";
    print "1. New download\n";
    print "2. Re-download from previous query\n";
    print "3. Delete a reference\n";
    print "4. Download images from subreddits posted by a user\n";
    print color('reset');
    print "Enter your choice ('exit' to exit): ";
    my $main_choice = <STDIN>;
    chomp $main_choice;
    last if $main_choice eq 'exit';

    my ($name, $num);

    if ($main_choice == 1) {
        print "Enter the username or subreddit (include u/ or r/ prefix): ";
        $name = <STDIN>;
        chomp $name;
        print "How many images do you want to download? (default is 9999): ";
        $num = <STDIN>;
        chomp $num;
        $num = $num ? $num : 9999;
        $history->{$name} = $num;
    } elsif ($main_choice == 2) {
        my @choices = keys %$history;
        if (@choices == 0) {
            print color('bold red');
            print "No previous queries found.\n";
            print color('reset');
            next MENU;
        }
        print "Select a previous query:\n";
        for my $i (0 .. $#choices) {
            print "$i. $choices[$i]\n";
        }
        print "Enter your choice: ";
        my $choice = <STDIN>;
        chomp $choice;
        if (defined $choices[$choice]) {
            $name = $choices[$choice];
            $num = $history->{$name};
        } else {
            print color('bold red');
            print "Invalid choice.\n";
            print color('reset');
            next MENU;
        }
    } elsif ($main_choice == 3) {
        delete_reference($history);
        next MENU;
    } elsif ($main_choice == 4) {
        print "Enter the username (without 'u/' prefix): ";
        my $username = <STDIN>;
        chomp $username;
        my @subreddits = search_subreddits($username);
        print "Subreddits posted by $username:\n";
        print join(", ", @subreddits), "\n";
        next MENU;
    } else {
        print color('bold red');
        print "Invalid choice.\n";
        print color('reset');
        next MENU;
    }

    # Prepare URL and directory based on user/subreddit
    my ($type, $dir);
    if ($name =~ /^u\//) {
        $type = "user";
        $dir = "downloads/user_images/$name";
        $name =~ s/^u\///;
        download_images("https://www.reddit.com/user/$name/submitted/.json?limit=100", $dir, $num);
    } elsif ($name =~ /^r\//) {
        $type = "subreddit";
        $dir = "downloads/subreddit_images/$name";
        $name =~ s/^r\///;
        download_images("https://www.reddit.com/r/$name/.json?limit=100", $dir, $num);
    } else {
        print color('bold red');
        print "Invalid input. Please prefix with 'u/' for users or 'r/' for subreddits.\n";
        print color('reset');
    }

    store($history, $log_file);
}
