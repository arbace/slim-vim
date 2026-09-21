package check

// The eleven whim checks whose whole body is tools/phasecheck.sh then
// tools/phasebuild.sh: every one of those phases rests its claim on the sweep
// and the symbol count, and says so in the header of its shell.
func init() {
	for _, n := range []string{"whim1", "whim2", "whim4", "whim5", "whim6", "whim7",
		"whim10", "whim13", "whim14", "whim15", "whim48"} {
		register(n, stdWhim(n))
	}
}
