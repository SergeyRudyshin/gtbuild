[![Build Status](https://travis-ci.org/SergeyRudyshin/gtbuild.svg?branch=master)](https://travis-ci.org/SergeyRudyshin/gtbuild)

# GTbuild 
_Doing More with Less_

## Main features
- allows specifying dependencies between scripts including transitive ones
- uses native command line interfaces of target systems
- avoids merge conflicts
- automatically generates a patch based on a Git diff
- a single shell script of 150 lines
- the runtime is 1/10 of a second

## How to install

Download [gtbuild.sh](gtbuild.sh) 

## How to use

Your project has to be under Git and has to have at least one annotated tag

You need to create a buildfile in your project directory
then run

``` shell
$> bash ./gtbuild.sh
```

## Tutorial

#### Algorithm

The tool works as folllows

1. takes all the files from the current directory hierarchy
2. sorts the list based on
    * firstly on the dependencies specified inside the files
    * then on its names
3. creates a patch by applying the filters specified in the build file (build.gts)
  * note that the filters support two modes (patch and full) (see [gtbuild.sh](gtbuild.sh) for details)
  * the build file contains several parameters (such as PAR_STATELESS_EXTS which specifies a list of file extensions not having any state)
  * the order in which the filters are listed impacts on the order in which the files will be included in the patch

#### Example

Suppose we have a bunch of files organazed as shown in [Directory structure] (#directory-structure)

Note that
* the files a.trg, a.tab, cr_002.sql have been changed since the last release
* the file a.tab depends on c.vw, a.trg on a.tab and b.tab on a.tab. Thus b.tab and a.trg transitively depends on c.vw

and we need to generate a patch file (see [Generated files] (#generated-files)) so that it could be installed on the production server

in order to do it we create a [Buildfile] (#buildfile) (see [gtbuild.sh](gtbuild.sh) for the parameters)

then run [gtbuild.sh](gtbuild.sh)

It generates a patch file and a full [Generated files] (#generated-files) .

The "full" file is used to track history of statefull objects and to resolve merge conflicts. 
It is supposed to be installed on a clear enviroment which is then to be compared with the patched one.

This tutorial is coded in a form of a unit test. See [gtbuild_test.sh](gtbuild_test.sh)
The test can be run as follows
``` shell
$> bash gtbuild_test.sh
```
it will create a temporary directory something like /tmp/2016-10-27... containing a zip file and auxilary files used to build it. 
Please have a look at them and especially at "lst.ALL.depends" (it has a dependecy tree).

That's it.

#### Directory structure
* comp_a/
   * a.pks
   * a.tab _(changed) (depends on c.vw)_ 
   * a.trg _(changed) (depends on a.tab)_
   * b.tab _(depends on a.tab)_
   * c.vw
* check_ver.sql
* parameters.sql
* patches/
   * cr_001.sql
   * cr_002.sql _(changed)_

#### Buildfile

###### Parameters

| Parameter | Value| Description |
| ---- | ----- | ----- |
| statless files | trg, vw, pks | List of file extensions not having any state |

###### Filters

| Filter | Files in patch mode | Files extensions in patch mode | Files in full mode | Files extensions in full mode |
| ---- | --- | ----- | ----- | ----- |
| parameters.sql    | ALL      | ANY      | ALL      | ANY |
| check_ver.sql     | ALL      | ANY      | NONE     | ANY |
| comp_a            | CHANGED  | LST      | ALL      | ANY |
| patches           | CHANGED  | ANY      | NONE     | ANY |

#### Generated files

| Patch Included files     |     | Patch Excluded files                                                           |     | Full-file Included files     |     | Full-file Excluded files |
| ----------------         | --- |                                                                            --- | --- | ----------------             | --- | ---                      |
| parameters.sql           |     | b.tab, a.pks, c.vw and, cr_001.sql  (have not been changed)                    |     | parameters.sql               |     | cr_001.sql, cr_002.sql   |
| check_ver.sql            |     | a.tab (is not in the list of "Statless files" even though it has been changed) |     | comp_a/a.pks                 |     | check_ver.sql            |
| comp_a/a.trg             |     |                                                                                |     | comp_a/c.vw                  |     |                          |
| patches/cr_002.sql       |     |                                                                                |     | comp_a/a.tab                 |     |                          |
|                          |     |                                                                                |     | comp_a/a.trg                 |     |                          |
|                          |     |                                                                                |     | comp_a/b.tab                 |     |                          |

