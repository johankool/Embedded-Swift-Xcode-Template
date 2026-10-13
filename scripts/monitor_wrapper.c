#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

int main(int argc, char *argv[]) {
    // Build the path to run.sh based on $HOME. run.sh flashes the board
    // and then starts monitor.sh. (This binary is still called "monitor",
    // because the Run scheme of existing projects points at it.)
    char *home = getenv("HOME");
    char path[1024];
    snprintf(path, sizeof(path), "%s/.espswift/scripts/run.sh", home);
    
    // Replace this process with the shell script
    execl("/bin/bash", "bash", path, NULL);
    
    // If execl returns, it failed
    return 1;
}
