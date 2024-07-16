#!/usr/bin/perl
use strict;
use warnings;
use File::Spec;
use Archive::Zip qw(:ERROR_CODES :CONSTANTS);
use Storable qw(retrieve store);

# Define directory paths
my $downloads_dir = 'downloads';
my $user_images_dir = File::Spec->catdir($downloads_dir, 'user_images');
my $subreddit_images_dir = File::Spec->catdir($downloads_dir, 'subreddit_images');
my $backup_dir = 'backup';

# Menu loop
MENU: while (1) {
    print "\n";
    print "Options:\n";
    print "1. Count total number of images in all directories\n";
    print "2. Check folder structure\n";
    print "3. Generate report\n";
    print "4. List subreddits and users from .dat file\n";
    print "5. Zip directories for backup\n";
    print "6. Exit\n";
    print "Enter your choice: ";
    my $choice = <STDIN>;
    chomp $choice;

    if ($choice eq '1') {
        count_total_images();
    } elsif ($choice eq '2') {
        check_folder_structure();
    } elsif ($choice eq '3') {
        generate_report();
    } elsif ($choice eq '4') {
        list_subreddits_users();
    } elsif ($choice eq '5') {
        zip_directories_for_backup();
    } elsif ($choice eq '6') {
        last MENU;  # Exit the menu loop
    } else {
        print "Invalid choice. Please enter a number between 1 and 6.\n";
    }
}

sub count_total_images {
    my $total_images = 0;

    # Count images in user_images_dir
    if (-d $user_images_dir) {
        my $count_user_images = count_images_in_directory($user_images_dir);
        print "Total images in user_images directory: $count_user_images\n";
        $total_images += $count_user_images;
    } else {
        print "User images directory does not exist: $user_images_dir\n";
    }

    # Count images in subreddit_images_dir
    if (-d $subreddit_images_dir) {
        my $count_subreddit_images = count_images_in_directory($subreddit_images_dir);
        print "Total images in subreddit_images directory: $count_subreddit_images\n";
        $total_images += $count_subreddit_images;
    } else {
        print "Subreddit images directory does not exist: $subreddit_images_dir\n";
    }

    print "Total number of images in all directories: $total_images\n";
}

sub count_images_in_directory {
    my ($dir) = @_;
    opendir(my $dh, $dir) or die "Cannot open directory $dir: $!\n";
    my @files = readdir($dh);  # Get all files and directories
    closedir $dh;

    my $image_count = 0;
    foreach my $file (@files) {
        next if $file =~ /^\./;  # Skip hidden files/directories
        my $full_path = File::Spec->catfile($dir, $file);
        if (-f $full_path) {
            # Check if the file is an image file (you can customize extensions as needed)
            if ($file =~ /\.(jpg|jpeg|png|gif)$/i) {
                $image_count++;
            }
        } elsif (-d $full_path) {
            # Recursively count images in subdirectories
            my $subdir_count = count_images_in_directory($full_path);
            $image_count += $subdir_count;
        } else {
            print "Skipping unknown file type: $full_path\n";
        }
    }

    return $image_count;
}

sub check_folder_structure {
    print "\nChecking folder structure:\n";

    # Check user_images_dir
    if (-d $user_images_dir) {
        print "User images directory exists: $user_images_dir\n";
    } else {
        print "User images directory does not exist: $user_images_dir\n";
    }

    # Check subreddit_images_dir
    if (-d $subreddit_images_dir) {
        print "Subreddit images directory exists: $subreddit_images_dir\n";
    } else {
        print "Subreddit images directory does not exist: $subreddit_images_dir\n";
    }
}

sub generate_report {
    print "\nGenerating report and writing to blagg.txt...\n";

    open(my $fh, '>', 'blagg.txt') or die "Cannot open file blagg.txt: $!\n";
    select $fh;  # Redirect STDOUT to the file handle

    list_subreddits_users();  # Run Option 4 functionality

    select STDOUT;  # Reset STDOUT to terminal
    close $fh;
    print "Report generation complete. Results saved to blagg.txt\n";
}

sub list_subreddits_users {
    print "\nListing subreddits and users from .dat file:\n";

    my $log_file = 'download_log.dat';
    my $history = -e $log_file ? retrieve($log_file) : {};

    unless (%$history) {
        print "No subreddits or users found in the .dat file.\n";
        return;
    }

    my @users;
    my @subreddits;

    foreach my $key (keys %$history) {
        if ($key =~ /^u\//) {
            push @users, $key;
        } elsif ($key =~ /^r\//) {
            push @subreddits, $key;
        }
    }

    if (@users) {
        print "Users:\n";
        foreach my $user (@users) {
            print "$user\n";
        }
    } else {
        print "No users found in .dat file.\n";
    }

    if (@subreddits) {
        print "Subreddits:\n";
        foreach my $subreddit (@subreddits) {
            print "$subreddit\n";
        }
    } else {
        print "No subreddits found in .dat file.\n";
    }
}

sub zip_directories_for_backup {
    print "\nZipping directories for backup...\n";
    print "so have a lovely sit down while this happens, it may take a while...\n";

    # Create the backup directory if it doesn't exist
    unless (-e $backup_dir and -d $backup_dir) {
        mkdir $backup_dir or die "Failed to create backup directory $backup_dir: $!\n";
    }

    # Zip user_images subdirectories
    if (-d $user_images_dir) {
        zip_subdirectories($user_images_dir);
    } else {
        print "User images directory does not exist: $user_images_dir\n";
    }

    # Zip subreddit_images subdirectories
    if (-d $subreddit_images_dir) {
        zip_subdirectories($subreddit_images_dir);
    } else {
        print "Subreddit images directory does not exist: $subreddit_images_dir\n";
    }
}

sub zip_subdirectories {
    my ($parent_dir) = @_;

    opendir my $dh, $parent_dir or die "Cannot open directory $parent_dir: $!\n";
    my @subdirs = grep { -d File::Spec->catdir($parent_dir, $_) && ! /^\.{1,2}$/ } readdir $dh;
    closedir $dh;

    foreach my $subdir (@subdirs) {
        my $subdir_path = File::Spec->catdir($parent_dir, $subdir);
        my $zip_file = File::Spec->catfile($backup_dir, "$subdir.zip");

        if (zip_directory($subdir_path, $zip_file)) {
            print "Created backup zip file for $subdir: $zip_file\n";
        } else {
            print "Failed to create backup zip file for $subdir\n";
        }
    }
}

sub zip_directory {
    my ($dir, $zip_file) = @_;

    # Create a new zip file
    my $zip = Archive::Zip->new();
    unless ($zip) {
        warn "Failed to create Archive::Zip object\n";
        return 0;
    }

    # Open the directory handle
    opendir my $dh, $dir or do {
        warn "Cannot open directory $dir: $!\n";
        return 0;
    };

    # Add files from directory to the zip file
    while (my $file = readdir $dh) {
        next if $file =~ /^\./;  # Skip hidden files/directories
        my $full_path = File::Spec->catfile($dir, $file);
        next unless -f $full_path;  # Only add regular files

        # Add file to the zip archive
        my $member = $zip->addFile($full_path, $file);
        unless ($member) {
            warn "Failed to add file $full_path to zip archive: $!\n";
            return 0;
        }
    }

    # Close the directory handle
    closedir $dh;

    # Write the zip file
    unless ($zip->writeToFileNamed($zip_file) == AZ_OK) {
        warn "Failed to write zip file $zip_file: $!\n";
        return 0;
    }

    return 1;
}

