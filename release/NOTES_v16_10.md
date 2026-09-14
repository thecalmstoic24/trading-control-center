# Trading Control Center 16.0-preview.10

Startup hotfix for preview.9: the embedded Windows Python runtime excludes the script directory from its module search path. The coordinator now adds its own directory before importing ratios, so the program can start normally.

Run the usual Install or Update shortcut on the Control Center computer. Existing VM agents are unchanged. All preview.9 planning and ratio features remain included.

Validation: isolated Python startup from an unrelated working directory, and the same check against files extracted from the actual installer. Both pass. Packaged agent files are byte-for-byte unchanged. No live trades were placed.
