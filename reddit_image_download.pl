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

sub download_image {
    my ($url, $date, $author, $dir, $ua, $hashes_ref) = @_;

    my $is_external = ($url !~ /^https?:\/\/(i\.)?redd\.it\//);

    my $filename = basename($url);
    $filename = "$date-$author-$filename";
    $filename = "external-$filename" if $is_external;

    # Strip 'u/' or 'r/' prefix from $dir
    $dir =~ s/^u\///;
    $dir =~ s/^r\///;

    my $path = "$dir/$filename";

    if (-e $path) {
        # Return 1 if the image was already downloaded
        return 1;
    }

    my $content = $ua->get($url)->decoded_content;
    return unless defined $content;

    my $hash = md5_hex($content);
    return if exists $hashes_ref->{$hash};

    open my $fh, '>', $path or die "Could not open $path: $!\n";
    binmode $fh;
    print $fh $content;
    close $fh;

    $hashes_ref->{$hash} = 1;
    print color('bold cyan');
    print "Downloaded image: $url\n";
    print color('reset');

    # Return 0 if the image was already downloaded
    return 0
}

# Function to download images
sub download_images {
    my ($download_url, $dir, $num) = @_;
    my $count = 0;
    my $non_image_count = 0;
    my $pdownloaded = 0;
    my %hashes;
    my $ua = LWP::UserAgent->new(agent => 'Mozilla/5.0');

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
            my $gallery_data = $post->{'data'}->{'gallery_data'}->{'items'};
            my $author = $post->{'data'}->{'author'};
            my $created_utc = $post->{'data'}->{'created_utc'};
            my $date = strftime("%d-%m-%Y", gmtime($created_utc));

            next unless defined $author;
            next unless defined $url;

            my @urls;
            if ($url =~ /\/gallery\//) {
                @urls = map { "https://i.redd.it/" . $_->{'media_id'} . ".jpg" } @$gallery_data;
            } elsif ($url =~ /\.(jpe?g|png|gif)$/i) {
                @urls = ($url);
            } else {
                $non_image_count++;
                next;
            }

            my $res;
            foreach my $phurl (@urls) {
                $res = download_image($phurl, $date, $author, $dir, $ua, \%hashes);
                $count++ if ($res == 0);
                $pdownloaded++ if ($res == 1);
            }
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
        print "Select a previous query: ('back' - back)\n";
        for my $i (0 .. $#choices) {
            print "$i. $choices[$i]\n";
        }
        print "Enter your choice: ";
        my $choice = <STDIN>;
        chomp $choice;
        next MENU if $choice eq 'back';
        if (defined $choices[$choice]) {
            $name = $choices[$choice];
            print "How many images do you want to download? (default is 9999): ";
            $num = <STDIN>;
            chomp $num;
            $num = $num ? $num : 9999;
            $history->{$name} = $num;
            print "Re-downloading $num images from $name\n";
        } else {
            print color('bold red');
            print "Invalid choice.\n";
            print color('reset');
            next MENU;
        }
    } elsif ($main_choice == 3) {
        delete_reference($history);
        store $history, $log_file;
        next MENU;
    } elsif ($main_choice == 4) {
        my @usernames = grep { /^u\// } keys %$history;
        if (@usernames == 0) {
            print color('bold red');
            print "No users found in .dat file.\n";
            print color('reset');
            next MENU;
        }

        print "Select a user to view their subreddits ('back' to go back):\n";
        for my $i (0 .. $#usernames) {
            print "$i. $usernames[$i]\n";
        }
        print "Enter your choice: ";
        my $user_choice = <STDIN>;
        chomp $user_choice;
        next MENU if $user_choice eq 'back';
        if (defined $usernames[$user_choice]) {
            my $username = substr($usernames[$user_choice], 2); # remove the 'u/' prefix
            my @subreddits = search_subreddits($username);
            if (@subreddits == 0) {
                print color('bold red');
                print "No subreddits found for user $username.\n";
                print color('reset');
                next MENU;
            }

            print "Select subreddits to download images from (comma-separated list of indices, 'back' to go back):\n";
            for my $i (0 .. $#subreddits) {
                print "$i. $subreddits[$i]\n";
            }
            print "Enter your choices: ";
            my $subreddit_choices = <STDIN>;
            chomp $subreddit_choices;
            next MENU if $subreddit_choices eq 'back';

            my @selected_indices = split /,\s*/, $subreddit_choices;
            my @selected_subreddits;
            my %subreddit_nums;

            foreach my $index (@selected_indices) {
                if (defined $subreddits[$index]) {
                    push @selected_subreddits, $subreddits[$index];
                } else {
                    print color('bold red');
                    print "Invalid choice: $index\n";
                    print color('reset');
                    next MENU;
                }
            }

            foreach my $subreddit (@selected_subreddits) {
                print "How many images do you want to download from r/$subreddit? (default is 9999): ";
                my $num_input = <STDIN>;
                chomp $num_input;
                $num = $num_input ? $num_input : 9999;
                $subreddit_nums{$subreddit} = $num;
                $history->{"r/$subreddit"} = $num;  # Log the subreddit and number of images
            }

            foreach my $subreddit (@selected_subreddits) {
                $name = "r/$subreddit";  # Set $name for constructing the URL
                $num = $subreddit_nums{$subreddit};
                my $dir = "downloads/subreddit_images/$subreddit";  # New directory structure
                make_path($dir);
                my $url = "https://www.reddit.com/r/$subreddit/new.json?limit=100";

                download_images($url, $dir, $num);
                # Save the updated history after downloading images
                store $history, $log_file;
            }
            next MENU;  # Add this line to skip the rest of the loop and avoid double downloading
        } else {
            print color('bold red');
            print "Invalid choice.\n";
            print color('reset');
            next MENU;
        }
    } else {
        print color('bold red');
        print "Invalid choice.\n";
        print color('reset');
        next MENU;
    }

    my $url;
    if ($name =~ m{^u/}) {
        $url = "https://www.reddit.com/user/" . substr($name, 2) . ".json?limit=100";
    } elsif ($name =~ m{^r/}) {
        $url = "https://www.reddit.com/r/" . substr($name, 2) . "/new.json?limit=100";
    } else {
        print color('bold red');
        print "Invalid name. Please enter a subreddit or user name in the format of u/name or r/name.\n";
        print color('reset');
        next MENU;
    }

    print color('bold green');
    print "Constructed URL: $url\n";
    print color('reset');

    if (!defined $url) {
        print color('bold red');
        print "URL is not defined. There might be an issue with URL construction.\n";
        print color('reset');
        next MENU;
    }

    # Adjust directory path based on $name without 'u/' or 'r/' prefix
    my $dir;
    if ($name =~ m{^u/(.+)$}) {
        $dir = "downloads/user_images/$1";  # Strip 'u/' prefix
    } elsif ($name =~ m{^r/(.+)$}) {
        $dir = "downloads/subreddit_images/$1";  # Strip 'r/' prefix
    }
    make_path($dir);

    print "Downloading images...\n";
    download_images($url, $dir, $num);

    # Save the updated history
    store $history, $log_file;
}
