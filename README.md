# conda-migrate.sh

a simple bash script that helps you to migrate your anaconda environment
from one path to another and takes care of all path conversions in your
environments
 
Syntax: `./conda-migrate.sh current_path new_path`

This tool is necessary because actually moving a conda installation tends to break
everything. Instead, it is necessary to:

  0) (optional) fix the prefix of a previous attempt to move anaconda installation
  
  1) install a fresh miniconda into the target directory
  
  2) export all of the environments from the old conda installation
  
  3) reinstall these environments into the new fresh miniconda install directory.

The reinstallation is done in two steps:

  1) try to install the exact packages as the original environment (using an
     explicit specification file)
  
  2) if that fails, install the packages using an environment file (`conda env export > environmentname.yml`)
  
  3) if that also fails, save the environment name to to a list of failed environments. 
     You'll have to tweak the environment.yml file yourself and install them using `conda env create -f environment.yml`

forked from [matthuska/conda-move](https://github.com/matthuska/conda-move)
 
Changelog: 
  * November 2020: Added options to fix prefix in botched conda installations,
                   renamed variables, added additional checks and warnings
                   throughout the script 
