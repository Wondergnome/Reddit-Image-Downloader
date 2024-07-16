Tested in Debian 12.
(list of perl deps to follow.)

I would place this script in a folder that can be easily found by any docker apps you may be using..

run it with "perl reddit_image_download.pl"

it downloads images stored on Reddit servers and creates a folder tree.
the tree is: downloads:
                - subreddit_images/subreddit
                - user_images/user
it stores the name of your downloads in a .dat file.


option 1) Either r/something or u/something and then the number of images you would like to obtain. This defaults to 9999.
option 2) Look at the .dat file and select an existing user or aubreddit. Good for checking for uodates..
option 3) Delete a reference from the .dat file and the corresponding directory.
option 4) This shows a list of users from the .dat file and then looks at the subreddita they have posted to.
          You can then make a comma separated list of the subreddits you wish to download from and the number of images from each of those subreddits.

bugfixes and updates of funtionality to follow. I didn't make this in python on purpose.
