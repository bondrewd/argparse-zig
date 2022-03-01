# Argparse Zig

A simple argument parser written in zig.

## Usage
Add this file to your project and import it from your entry point (main.zig).

First, you will need to build a parser type. The function ArgumentParser takes
two arguments: AppInfo and AppOptionPositional. AppInfo is a struct that contains
three fields describing your app, whereas AppOptionPositional is a struct that
allows you to control how options are parsed.

After you have build your parser, you only need to use the Parser associated
function parseArguments. That is all!

I have also added some examples showing how to build an argument parser.
