// surfetch — a fast system fetch with random anime ASCII art.
//
// All info is read straight from /proc and /sys (no subprocesses), so a run takes a few ms.
//
//	surfetch                 random art + system info (info block matches the art's height)
//	surfetch --change        pick the art to show (or "random"), with previews when fzf is installed
//	surfetch --add [FILE]    add your own art: .txt, or an image (png/jpg/gif) converted to braille;
//	                         with no FILE, paste art into $EDITOR (or pipe it on stdin)
//	surfetch --list          list arts            surfetch --art NAME     show a specific art
//	surfetch --remove NAME   remove one of your arts
package main

import (
	"bufio"
	"embed"
	"fmt"
	"image"
	_ "image/gif"
	_ "image/jpeg"
	_ "image/png"
	"io"
	"math"
	"math/rand/v2"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"syscall"
	"time"
	"unicode/utf8"
	"unsafe"
)

//go:embed arts/*.txt
var builtinArts embed.FS

var (
	home     = os.Getenv("HOME")
	userArts = envOr("XDG_DATA_HOME", home+"/.local/share") + "/surfetch/arts"
	confFile = envOr("XDG_CONFIG_HOME", home+"/.config") + "/surfetch/config"
	cacheDir = envOr("XDG_CACHE_HOME", home+"/.cache") + "/surfetch"
)

func envOr(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

// ---------------------------------------------------------------- arts

type art struct {
	name  string
	lines []string
	user  bool
}

func loadArt(name string) (art, bool) {
	if b, err := os.ReadFile(filepath.Join(userArts, name+".txt")); err == nil {
		return art{name, splitArt(string(b)), true}, true
	}
	if b, err := builtinArts.ReadFile("arts/" + name + ".txt"); err == nil {
		return art{name, splitArt(string(b)), false}, true
	}
	return art{}, false
}

func artNames() (builtin, user []string) { return catNames("") }

// Collections are your own folders: ~/.local/share/surfetch/arts/<collection>/*.txt
// Their arts are named "<collection>/<name>" and shown with: surfetch <collection>
func collections() []string {
	var cs []string
	es, _ := os.ReadDir(userArts)
	for _, e := range es {
		if e.IsDir() {
			cs = append(cs, e.Name())
		}
	}
	sort.Strings(cs)
	return cs
}

func catNames(cat string) (builtin, user []string) {
	dir, prefix := "arts", ""
	if cat != "" {
		dir, prefix = "arts/"+cat, cat+"/"
	}
	es, _ := builtinArts.ReadDir(dir)
	for _, e := range es {
		if strings.HasSuffix(e.Name(), ".txt") {
			builtin = append(builtin, prefix+strings.TrimSuffix(e.Name(), ".txt"))
		}
	}
	if es, err := os.ReadDir(filepath.Join(userArts, cat)); err == nil {
		for _, e := range es {
			if strings.HasSuffix(e.Name(), ".txt") {
				user = append(user, prefix+strings.TrimSuffix(e.Name(), ".txt"))
			}
		}
	}
	sort.Strings(builtin)
	sort.Strings(user)
	return
}

func splitArt(s string) []string {
	s = strings.ReplaceAll(strings.ReplaceAll(s, "\r", ""), "\t", "    ")
	ls := strings.Split(strings.TrimRight(s, "\n "), "\n")
	for len(ls) > 0 && strings.TrimSpace(ls[0]) == "" { // drop leading blank lines
		ls = ls[1:]
	}
	// strip common left indentation
	min := -1
	for _, l := range ls {
		if strings.TrimSpace(l) == "" {
			continue
		}
		n := len(l) - len(strings.TrimLeft(l, " "))
		if min < 0 || n < min {
			min = n
		}
	}
	for i, l := range ls {
		if len(l) >= min && min > 0 {
			ls[i] = strings.TrimRight(l[min:], " ")
		} else {
			ls[i] = strings.TrimRight(l, " ")
		}
	}
	return ls
}

// display width: East Asian wide / fullwidth characters take two columns
func width(s string) int {
	w := 0
	for _, r := range s {
		switch {
		case r < 0x1100:
			w++
		case (r >= 0x1100 && r <= 0x115F) || (r >= 0x2E80 && r <= 0xA4CF && r != 0x303F) ||
			(r >= 0xAC00 && r <= 0xD7A3) || (r >= 0xF900 && r <= 0xFAFF) || (r >= 0xFE30 && r <= 0xFE4F) ||
			(r >= 0xFF00 && r <= 0xFF60) || (r >= 0xFFE0 && r <= 0xFFE6) || (r >= 0x1F300 && r <= 0x1FAFF) ||
			(r >= 0x20000 && r <= 0x3FFFD):
			w += 2
		default:
			w++
		}
	}
	return w
}

func pinned() string {
	b, err := os.ReadFile(confFile)
	if err != nil {
		return "random"
	}
	for _, l := range strings.Split(string(b), "\n") {
		if v, ok := strings.CutPrefix(strings.TrimSpace(l), "art="); ok && v != "" {
			return v
		}
	}
	return "random"
}

func setPinned(name string) error {
	os.MkdirAll(filepath.Dir(confFile), 0o755)
	return os.WriteFile(confFile, []byte("art="+name+"\n"), 0o644)
}

// ---------------------------------------------------------------- colours

type rgb struct{ r, g, b int }

var gradients = [][2]rgb{
	{{255, 121, 198}, {189, 147, 249}}, // sakura pink -> lavender
	{{130, 196, 255}, {198, 120, 221}}, // sky -> violet
	{{255, 154, 77}, {255, 99, 132}},   // amber -> rose
	{{127, 215, 224}, {152, 195, 121}}, // cyan -> green
	{{255, 216, 138}, {255, 121, 198}}, // gold -> pink
	{{189, 147, 249}, {130, 196, 255}}, // lavender -> sky
}

func lerp(a, b rgb, t float64) rgb {
	m := func(x, y int) int { return x + int(float64(y-x)*t) }
	return rgb{m(a.r, b.r), m(a.g, b.g), m(a.b, b.b)}
}

func fg(c rgb) string { return fmt.Sprintf("\x1b[38;2;%d;%d;%dm", c.r, c.g, c.b) }

const reset = "\x1b[0m"

// ---------------------------------------------------------------- system info (no subprocesses)

func readTrim(p string) string {
	b, _ := os.ReadFile(p)
	return strings.TrimSpace(string(b))
}

func osName() string {
	b, _ := os.ReadFile("/etc/os-release")
	for _, l := range strings.Split(string(b), "\n") {
		if v, ok := strings.CutPrefix(l, "PRETTY_NAME="); ok {
			var u syscall.Utsname
			syscall.Uname(&u)
			return strings.Trim(v, `"`) + " " + cstr(u.Machine[:])
		}
	}
	return "Linux"
}

func cstr(b []int8) string {
	s := make([]byte, 0, len(b))
	for _, c := range b {
		if c == 0 {
			break
		}
		s = append(s, byte(c))
	}
	return string(s)
}

func hostModel() string {
	n := readTrim("/sys/class/dmi/id/product_name")
	v := readTrim("/sys/class/dmi/id/product_version")
	if v != "" && !strings.Contains(strings.ToLower(v), "default") && !strings.Contains(n, v) {
		n += " (" + v + ")"
	}
	return n
}

func uptime() string {
	f := strings.Fields(readTrim("/proc/uptime"))
	if len(f) == 0 {
		return ""
	}
	s, _ := strconv.ParseFloat(f[0], 64)
	d, h, m := int(s)/86400, int(s)%86400/3600, int(s)%3600/60
	var p []string
	if d > 0 {
		p = append(p, fmt.Sprintf("%dd", d))
	}
	if h > 0 {
		p = append(p, fmt.Sprintf("%dh", h))
	}
	p = append(p, fmt.Sprintf("%dm", m))
	return strings.Join(p, " ")
}

func packages() string {
	es, err := os.ReadDir("/var/lib/pacman/local")
	if err != nil {
		return ""
	}
	n := 0
	for _, e := range es {
		if e.IsDir() {
			n++
		}
	}
	return fmt.Sprintf("%d (pacman)", n)
}

func procComm(pid int) (string, int) {
	b, err := os.ReadFile("/proc/" + strconv.Itoa(pid) + "/stat")
	if err != nil {
		return "", 0
	}
	s := string(b)
	l, r := strings.IndexByte(s, '('), strings.LastIndexByte(s, ')')
	if l < 0 || r < l {
		return "", 0
	}
	f := strings.Fields(s[r+1:])
	pp := 0
	if len(f) > 1 {
		pp, _ = strconv.Atoi(f[1])
	}
	return s[l+1 : r], pp
}

var shells = map[string]bool{"fish": true, "bash": true, "zsh": true, "sh": true, "nu": true, "dash": true, "ksh": true, "tcsh": true, "elvish": true, "xonsh": true}

func shellAndTerm() (shell, term string) {
	name, pid := procComm(os.Getppid())
	if shells[name] {
		shell = name
	} else {
		shell = filepath.Base(os.Getenv("SHELL"))
	}
	if name == "" {
		pid = 0
	}
	for i := 0; pid > 1 && i < 12; i++ {
		var n string
		n, pid = procComm(pid)
		if n != "" && !shells[n] && n != "sudo" && n != "su" && n != "script" && n != "tmux: server" {
			term = n
			break
		}
	}
	if t := os.Getenv("TERM_PROGRAM"); t != "" {
		term = t
	}
	return
}

func desktop() string {
	if os.Getenv("HYPRLAND_INSTANCE_SIGNATURE") != "" {
		return "Hyprland"
	}
	if d := os.Getenv("XDG_CURRENT_DESKTOP"); d != "" {
		return d
	}
	return os.Getenv("DESKTOP_SESSION")
}

func cpu() string {
	f, err := os.Open("/proc/cpuinfo")
	if err != nil {
		return ""
	}
	defer f.Close()
	model, n := "", 0
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		l := sc.Text()
		if strings.HasPrefix(l, "processor") {
			n++
		} else if model == "" && strings.HasPrefix(l, "model name") {
			model = strings.TrimSpace(l[strings.IndexByte(l, ':')+1:])
		}
	}
	for _, s := range []string{"(R)", "(TM)", "CPU ", "Processor", "with Radeon Graphics", "13th Gen ", "12th Gen ", "11th Gen ", "14th Gen "} {
		model = strings.ReplaceAll(model, s, "")
	}
	model = strings.Join(strings.Fields(model), " ")
	if mhz, err := strconv.Atoi(readTrim("/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq")); err == nil {
		return fmt.Sprintf("%s (%d) @ %.2f GHz", model, n, float64(mhz)/1e6)
	}
	return fmt.Sprintf("%s (%d)", model, n)
}

// GPU name via pci.ids, cached after the first lookup
func gpu() string {
	devs, _ := filepath.Glob("/sys/bus/pci/devices/*")
	var ids []string
	for _, d := range devs {
		if strings.HasPrefix(readTrim(d+"/class"), "0x03") {
			v := strings.TrimPrefix(readTrim(d+"/vendor"), "0x")
			p := strings.TrimPrefix(readTrim(d+"/device"), "0x")
			ids = append(ids, v+":"+p)
		}
	}
	if len(ids) == 0 {
		return ""
	}
	key := strings.Join(ids, ",")
	cache := cacheDir + "/gpu"
	if b, err := os.ReadFile(cache); err == nil {
		if k, v, ok := strings.Cut(strings.TrimSpace(string(b)), "="); ok && k == key {
			return v
		}
	}
	names := lookupPCI(ids)
	out := strings.Join(names, ", ")
	os.MkdirAll(cacheDir, 0o755)
	os.WriteFile(cache, []byte(key+"="+out+"\n"), 0o644)
	return out
}

func lookupPCI(ids []string) []string {
	want := map[string]int{}
	res := make([]string, len(ids))
	for i, id := range ids {
		want[id] = i
		res[i] = id
	}
	f, err := os.Open("/usr/share/hwdata/pci.ids")
	if err != nil {
		return res
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	vendor, vname := "", ""
	for sc.Scan() {
		l := sc.Text()
		if l == "" || l[0] == '#' {
			continue
		}
		if l[0] != '\t' && len(l) > 6 {
			vendor, vname = l[:4], strings.TrimSpace(l[4:])
			continue
		}
		if l[0] == '\t' && (len(l) < 2 || l[1] != '\t') && len(l) > 7 {
			if i, ok := want[vendor+":"+l[1:5]]; ok {
				dev := strings.TrimSpace(l[5:])
				if b := strings.IndexByte(dev, '['); b >= 0 { // "Raptor Lake-P [Iris Xe Graphics]" -> bracket part
					if e := strings.IndexByte(dev[b:], ']'); e > 0 {
						dev = dev[b+1 : b+e]
					}
				}
				vn := strings.Fields(vname)[0]
				if strings.HasPrefix(vname, "Advanced Micro") {
					vn = "AMD"
				} else if strings.HasPrefix(vname, "NVIDIA") {
					vn = "NVIDIA"
				}
				res[i] = vn + " " + dev
			}
		}
	}
	return res
}

func memory() string {
	b, _ := os.ReadFile("/proc/meminfo")
	var tot, avail float64
	for _, l := range strings.Split(string(b), "\n") {
		f := strings.Fields(l)
		if len(f) < 2 {
			continue
		}
		v, _ := strconv.ParseFloat(f[1], 64)
		switch f[0] {
		case "MemTotal:":
			tot = v
		case "MemAvailable:":
			avail = v
		}
	}
	if tot == 0 {
		return ""
	}
	used := tot - avail
	return fmt.Sprintf("%.1f / %.1f GiB (%d%%)", used/1048576, tot/1048576, int(used*100/tot))
}

func disk() string {
	var s syscall.Statfs_t
	if syscall.Statfs("/", &s) != nil {
		return ""
	}
	tot := float64(s.Blocks) * float64(s.Bsize)
	used := tot - float64(s.Bavail)*float64(s.Bsize)
	return fmt.Sprintf("%.0f / %.0f GiB (%d%%)", used/(1<<30), tot/(1<<30), int(used*100/tot))
}

func battery() string {
	bs, _ := filepath.Glob("/sys/class/power_supply/BAT*")
	for _, b := range bs {
		if c := readTrim(b + "/capacity"); c != "" {
			st := readTrim(b + "/status")
			if st == "Not charging" {
				st = "Full"
			}
			return c + "% [" + st + "]"
		}
	}
	return ""
}

func resolution() string {
	cs, _ := filepath.Glob("/sys/class/drm/card*-*")
	var out []string
	for _, c := range cs {
		if readTrim(c+"/status") != "connected" {
			continue
		}
		m := strings.SplitN(readTrim(c+"/modes"), "\n", 2)[0]
		if m != "" {
			out = append(out, m)
		}
	}
	return strings.Join(out, ", ")
}

func swap() string {
	b, _ := os.ReadFile("/proc/meminfo")
	var tot, free float64
	for _, l := range strings.Split(string(b), "\n") {
		f := strings.Fields(l)
		if len(f) < 2 {
			continue
		}
		v, _ := strconv.ParseFloat(f[1], 64)
		switch f[0] {
		case "SwapTotal:":
			tot = v
		case "SwapFree:":
			free = v
		}
	}
	if tot == 0 {
		return ""
	}
	return fmt.Sprintf("%.1f / %.1f GiB", (tot-free)/1048576, tot/1048576)
}

func loadAvg() string {
	f := strings.Fields(readTrim("/proc/loadavg"))
	if len(f) < 3 {
		return ""
	}
	return f[0] + ", " + f[1] + ", " + f[2]
}

func processes() string {
	es, err := os.ReadDir("/proc")
	if err != nil {
		return ""
	}
	n := 0
	for _, e := range es {
		if c := e.Name()[0]; c >= '0' && c <= '9' {
			n++
		}
	}
	return strconv.Itoa(n)
}

func cpuTemp() string {
	hs, _ := filepath.Glob("/sys/class/hwmon/hwmon*")
	for _, h := range hs {
		switch readTrim(h + "/name") {
		case "coretemp", "k10temp", "zenpower", "cpu_thermal":
			if v, err := strconv.Atoi(readTrim(h + "/temp1_input")); err == nil {
				return fmt.Sprintf("%.0f°C", float64(v)/1000)
			}
		}
	}
	return ""
}

func localIP() string {
	ifs, _ := net.Interfaces()
	for _, i := range ifs {
		if i.Flags&net.FlagUp == 0 || i.Flags&net.FlagLoopback != 0 {
			continue
		}
		as, _ := i.Addrs()
		for _, a := range as {
			if n, ok := a.(*net.IPNet); ok && n.IP.To4() != nil {
				return n.String() + " (" + i.Name + ")"
			}
		}
	}
	return ""
}

// terminal width: fzf preview pane, else the tty, else $COLUMNS
func termCols() int {
	if v, err := strconv.Atoi(os.Getenv("FZF_PREVIEW_COLUMNS")); err == nil && v > 0 {
		return v
	}
	var ws struct{ row, col, x, y uint16 }
	if _, _, e := syscall.Syscall(syscall.SYS_IOCTL, os.Stdout.Fd(), syscall.TIOCGWINSZ, uintptr(unsafe.Pointer(&ws))); e == 0 && ws.col > 0 {
		return int(ws.col)
	}
	if v, err := strconv.Atoi(os.Getenv("COLUMNS")); err == nil && v > 0 {
		return v
	}
	return 200
}

// fitArt scales braille art down (never up) to at most maxH lines and maxW columns,
// so tall or wide art still lines up with the info block. Text (non-braille) art is left as is.
func fitArt(a art, maxH, maxW int) art {
	H, W, br, other := len(a.lines), 0, 0, 0
	for _, l := range a.lines {
		W = max(W, width(l))
		for _, r := range l {
			if r >= 0x2800 && r <= 0x28FF {
				br++
			} else if r != ' ' {
				other++
			}
		}
	}
	if br == 0 || other*5 > br || (H <= maxH && W <= maxW) || maxH < 2 || maxW < 4 {
		return a
	}
	s := math.Min(float64(maxH)/float64(H), float64(maxW)/float64(W))
	nh, nw := max(1, int(float64(H)*s)), max(1, int(math.Round(float64(W)*s)))
	sw, sh, dw, dh := W*2, H*4, nw*2, nh*4
	src := make([]bool, sw*sh)
	dots := [4][2]int{{0x01, 0x08}, {0x02, 0x10}, {0x04, 0x20}, {0x40, 0x80}}
	on := 0
	for y, l := range a.lines {
		x := 0
		for _, r := range l {
			if o := int(r) - 0x2800; o >= 0 && o <= 0xFF {
				for dy := 0; dy < 4; dy++ {
					for dx := 0; dx < 2; dx++ {
						if o&dots[dy][dx] != 0 {
							src[(y*4+dy)*sw+x*2+dx] = true
							on++
						}
					}
				}
			}
			x++
		}
	}
	// adaptive threshold: keeps thin lines in sparse line-art, keeps contrast in dense art
	thr := math.Max(0.2, math.Min(0.5, float64(on)/float64(sw*sh)))
	var out []string
	for cy := 0; cy < nh; cy++ {
		var sb strings.Builder
		for cx := 0; cx < nw; cx++ {
			c := 0
			for dy := 0; dy < 4; dy++ {
				for dx := 0; dx < 2; dx++ {
					px, py := cx*2+dx, cy*4+dy
					x0, x1 := px*sw/dw, max((px+1)*sw/dw, px*sw/dw+1)
					y0, y1 := py*sh/dh, max((py+1)*sh/dh, py*sh/dh+1)
					n, k := 0, 0
					for yy := y0; yy < y1 && yy < sh; yy++ {
						for xx := x0; xx < x1 && xx < sw; xx++ {
							n++
							if src[yy*sw+xx] {
								k++
							}
						}
					}
					if n > 0 && float64(k)/float64(n) >= thr {
						c |= dots[dy][dx]
					}
				}
			}
			sb.WriteRune(rune(0x2800 + c))
		}
		out = append(out, strings.TrimRight(sb.String(), " "))
	}
	return art{a.name, out, a.user}
}

func artWidth(a art) int {
	w := 0
	for _, l := range a.lines {
		w = max(w, width(l))
	}
	return w
}

// renderStacked: narrow terminals get the art on top, full info below.
func renderStacked(a art, fs []field, g [2]rgb, user, host string) {
	accent := fg(g[1])
	var out strings.Builder
	out.WriteString("\n")
	n := len(a.lines)
	for i, l := range a.lines {
		out.WriteString("  " + fg(lerp(g[0], g[1], float64(i)/float64(max(n-1, 1)))) + l + reset + "\n")
	}
	out.WriteString("\n  " + accent + "\x1b[1m" + user + reset + "@" + accent + "\x1b[1m" + host + reset + "\n")
	out.WriteString("  " + fg(g[0]) + strings.Repeat("─", utf8.RuneCountInString(user+"@"+host)) + reset + "\n")
	lw := 0
	for _, f := range fs {
		lw = max(lw, len(f.label))
	}
	for _, f := range fs {
		out.WriteString("  " + accent + "\x1b[1m" + f.label + reset + strings.Repeat(" ", lw-len(f.label)) + "  " + f.value + "\n")
	}
	out.WriteString("\n")
	io.WriteString(os.Stdout, out.String())
}

// ---------------------------------------------------------------- render

type field struct {
	label, value string
	prio         int // lower = kept first when the art is short
}

func render(a art) {
	g := gradients[rand.IntN(len(gradients))]
	accent := fg(g[1])
	user, _ := os.LookupEnv("USER")
	host := readTrim("/proc/sys/kernel/hostname")
	shell, term := shellAndTerm()

	fields := []field{
		{"OS", osName(), 1}, {"Host", hostModel(), 5}, {"Kernel", readTrim("/proc/sys/kernel/osrelease"), 2},
		{"Uptime", uptime(), 3}, {"Packages", packages(), 6}, {"Shell", shell, 4}, {"WM", desktop(), 4},
		{"Terminal", term, 7}, {"CPU", cpu(), 2}, {"GPU", gpu(), 3}, {"Memory", memory(), 2},
		{"Disk (/)", disk(), 6}, {"Battery", battery(), 5}, {"Display", resolution(), 8},
		{"Swap", swap(), 9}, {"CPU Temp", cpuTemp(), 9}, {"Load", loadAvg(), 10}, {"Processes", processes(), 11},
		{"Local IP", localIP(), 11}, {"Locale", os.Getenv("LANG"), 12}, {"Date", time.Now().Format("Mon 2 Jan 2006, 15:04"), 12},
	}
	var fs []field
	for _, f := range fields {
		if f.value != "" {
			fs = append(fs, f)
		}
	}

	const fixed = 4 // title, rule, blank, palette
	// fit big braille art: no taller than the full info block, no wider than the terminal allows
	infoW := len(user) + 1 + len(host)
	lwAll := 0
	for _, f := range fs {
		lwAll = max(lwAll, len(f.label))
	}
	for _, f := range fs {
		infoW = max(infoW, lwAll+2+width(f.value))
	}
	cols := termCols()
	if room := cols - infoW - 8; room < 30 && artWidth(a) > room {
		renderStacked(fitArt(a, 30, cols-4), fs, g, user, host)
		return
	}
	a = fitArt(a, len(fs)+fixed, cols-infoW-8)

	H := len(a.lines)
	room := H - fixed
	if room < 4 {
		room = 4
	}
	if len(fs) > room { // drop lowest-priority fields until the info fits the art
		keep := make([]field, len(fs))
		copy(keep, fs)
		sort.SliceStable(keep, func(i, j int) bool { return keep[i].prio < keep[j].prio })
		allowed := map[string]bool{}
		for _, f := range keep[:room] {
			allowed[f.label] = true
		}
		var trimmed []field
		for _, f := range fs {
			if allowed[f.label] {
				trimmed = append(trimmed, f)
			}
		}
		fs = trimmed
	}

	title := user + "@" + host
	info := []string{
		accent + "\x1b[1m" + user + reset + "@" + accent + "\x1b[1m" + host + reset,
		fg(g[0]) + strings.Repeat("─", utf8.RuneCountInString(title)) + reset,
	}
	lw := 0
	for _, f := range fs {
		if len(f.label) > lw {
			lw = len(f.label)
		}
	}
	for _, f := range fs {
		info = append(info, accent+"\x1b[1m"+f.label+reset+strings.Repeat(" ", lw-len(f.label))+"  "+f.value)
	}
	info = append(info, "")
	var pal strings.Builder
	for i := 0; i < 8; i++ {
		fmt.Fprintf(&pal, "\x1b[4%dm   ", i)
	}
	pal.WriteString(reset + " ")
	for i := 0; i < 6; i++ {
		pal.WriteString(fg(lerp(g[0], g[1], float64(i)/5)) + "●" + " ")
	}
	info = append(info, pal.String()+reset)

	// vertically centre the shorter block so text and logo are the same height
	aw := 0
	for _, l := range a.lines {
		if w := width(l); w > aw {
			aw = w
		}
	}
	n := max(H, len(info))
	artTop, infoTop := (n-H)/2, (n-len(info))/2

	var out strings.Builder
	out.WriteString("\n")
	for i := 0; i < n; i++ {
		al := ""
		if j := i - artTop; j >= 0 && j < H {
			al = a.lines[j]
		}
		t := float64(i) / float64(max(n-1, 1))
		out.WriteString("  " + fg(lerp(g[0], g[1], t)) + al + reset + strings.Repeat(" ", aw-width(al)+4))
		if j := i - infoTop; j >= 0 && j < len(info) {
			out.WriteString(info[j])
		}
		out.WriteString("\n")
	}
	out.WriteString("\n")
	io.WriteString(os.Stdout, out.String())
}

func pickArt() art {
	if p := pinned(); p != "random" {
		if a, ok := loadArt(p); ok {
			return a
		}
	}
	b, u := artNames()
	all := append(b, u...)
	a, _ := loadArt(all[rand.IntN(len(all))])
	return a
}

func pickFrom(collection string) art {
	b, u := catNames(collection)
	all := append(b, u...)
	if len(all) == 0 {
		fail("collection " + collection + " is empty")
	}
	a, _ := loadArt(all[rand.IntN(len(all))])
	return a
}

// ---------------------------------------------------------------- commands

func cmdChange() {
	b, u := artNames()
	for _, c := range collections() {
		cb, cu := catNames(c)
		b, u = append(b, cb...), append(u, cu...)
	}
	cur := pinned()
	if _, err := exec.LookPath("fzf"); err == nil {
		self, _ := os.Executable()
		list := "random\n" + strings.Join(append(b, u...), "\n") + "\n"
		c := exec.Command("fzf", "--prompt", "art ("+cur+") > ", "--height", "~100%", "--layout", "reverse",
			"--preview", self+" --preview-art {}", "--preview-window", "right,60%")
		c.Stdin = strings.NewReader(list)
		c.Stderr = os.Stderr
		outb, err := c.Output()
		if err != nil {
			return
		}
		choice := strings.TrimSpace(string(outb))
		setPinned(choice)
		fmt.Println("surfetch art:", choice)
		return
	}
	all := append([]string{"random"}, append(b, u...)...)
	for i, n := range all {
		mark := " "
		if n == cur {
			mark = "*"
		}
		fmt.Printf(" %s %2d) %s\n", mark, i, n)
	}
	fmt.Print("choose number: ")
	var i int
	if _, err := fmt.Scan(&i); err != nil || i < 0 || i >= len(all) {
		fmt.Println("cancelled")
		return
	}
	setPinned(all[i])
	fmt.Println("surfetch art:", all[i])
}

func cmdAdd(args []string) {
	var src, name string
	cols, invert, dither, cat := 40, false, false, ""
	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "--name":
			i++
			if i < len(args) {
				name = args[i]
			}
		case "--width":
			i++
			if i < len(args) {
				cols, _ = strconv.Atoi(args[i])
			}
		case "--invert":
			invert = true
		case "--dither":
			dither = true
		case "--to":
			i++
			if i < len(args) {
				cat = args[i]
			}
		default:
			src = args[i]
		}
	}
	var text string
	switch {
	case src != "" && isImage(src):
		t, err := imageToBraille(src, cols, invert, dither)
		if err != nil {
			fail("could not convert image: " + err.Error())
		}
		text = t
	case src != "":
		b, err := os.ReadFile(src)
		if err != nil {
			fail(err.Error())
		}
		text = string(b)
	default:
		if fi, _ := os.Stdin.Stat(); fi.Mode()&os.ModeCharDevice == 0 {
			b, _ := io.ReadAll(os.Stdin)
			text = string(b)
		} else {
			text = fromEditor()
		}
	}
	lines := splitArt(text)
	if len(lines) == 0 || strings.TrimSpace(strings.Join(lines, "")) == "" {
		fail("art is empty, nothing added")
	}
	if name == "" {
		if src != "" {
			name = strings.TrimSuffix(filepath.Base(src), filepath.Ext(src))
		} else {
			name = "art-" + time.Now().Format("20060102-150405")
		}
	}
	name = strings.Map(func(r rune) rune {
		if r == '/' || r == ' ' {
			return '-'
		}
		return r
	}, name)
	if cat != "" {
		name = cat + "/" + name
	}
	os.MkdirAll(filepath.Dir(filepath.Join(userArts, name+".txt")), 0o755)
	if err := os.WriteFile(filepath.Join(userArts, name+".txt"), []byte(strings.Join(lines, "\n")+"\n"), 0o644); err != nil {
		fail(err.Error())
	}
	a, _ := loadArt(name)
	render(a)
	fmt.Printf("added art %q (%d lines). Show it with: surfetch --art %s\n", name, len(lines), name)
}

func fromEditor() string {
	ed := envOr("VISUAL", envOr("EDITOR", "nano"))
	f, err := os.CreateTemp("", "surfetch-*.txt")
	if err != nil {
		fail(err.Error())
	}
	f.WriteString("")
	f.Close()
	defer os.Remove(f.Name())
	c := exec.Command("sh", "-c", ed+` "$1"`, "sh", f.Name())
	c.Stdin, c.Stdout, c.Stderr = os.Stdin, os.Stdout, os.Stderr
	if err := c.Run(); err != nil {
		fail("editor failed: " + err.Error())
	}
	b, _ := os.ReadFile(f.Name())
	return string(b)
}

func isImage(p string) bool {
	switch strings.ToLower(filepath.Ext(p)) {
	case ".png", ".jpg", ".jpeg", ".gif":
		return true
	}
	return false
}

// imageToBraille renders an image as braille dots (2x4 per character) with Floyd–Steinberg dithering.
func imageToBraille(path string, cols int, invert, dither bool) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close()
	img, _, err := image.Decode(f)
	if err != nil {
		return "", err
	}
	bnd := img.Bounds()
	iw, ih := bnd.Dx(), bnd.Dy()
	if cols < 8 {
		cols = 8
	}
	W := cols * 2
	H := int(float64(W)*float64(ih)/float64(iw)+3) / 4 * 4
	lum := make([]float64, W*H)
	var sum float64
	for y := 0; y < H; y++ { // box-filter downsample to W x H luminance
		y0, y1 := bnd.Min.Y+y*ih/H, bnd.Min.Y+(y+1)*ih/H
		for x := 0; x < W; x++ {
			x0, x1 := bnd.Min.X+x*iw/W, bnd.Min.X+(x+1)*iw/W
			var s, n float64
			for yy := y0; yy < max(y1, y0+1); yy++ {
				for xx := x0; xx < max(x1, x0+1); xx++ {
					r, g, b, a := img.At(xx, yy).RGBA()
					l := (0.2126*float64(r) + 0.7152*float64(g) + 0.0722*float64(b)) / 65535
					al := float64(a) / 65535
					s += l*al + (1 - al) // transparent pixels count as white
					n++
				}
			}
			lum[y*W+x] = s / n
			sum += s / n
		}
	}
	// Otsu threshold: best light/dark split for this image
	var hist [256]int
	for _, v := range lum {
		hist[min(255, max(0, int(v*255)))]++
	}
	total, sumAll := float64(W*H), 0.0
	for i, c := range hist {
		sumAll += float64(i * c)
	}
	var wB, sumB, best float64
	thr := 0.5
	for t, c := range hist {
		wB += float64(c)
		if wB == 0 || wB == total {
			continue
		}
		sumB += float64(t * c)
		mB, mF := sumB/wB, (sumAll-sumB)/(total-wB)
		if v := wB * (total - wB) * (mB - mF) * (mB - mF); v > best {
			best, thr = v, (float64(t)+0.5)/255
		}
	}
	// light background (line art) -> draw dark pixels; dark background -> draw bright ones
	drawDark := sum/float64(W*H) > 0.5
	if invert {
		drawDark = !drawDark
	}
	on := make([]bool, W*H)
	for y := 0; y < H; y++ {
		for x := 0; x < W; x++ {
			i := y*W + x
			v := lum[i]
			if drawDark {
				v = 1 - v
			}
			cut := 0.5
			if !dither {
				cut = thr
				if drawDark {
					cut = 1 - thr
				}
			}
			bit := v > cut
			on[i] = bit
			if !dither {
				continue
			}
			e := v
			if bit {
				e = v - 1
			}
			if drawDark {
				e = -e
			}
			spread := func(dx, dy int, w float64) {
				if xx, yy := x+dx, y+dy; xx >= 0 && xx < W && yy < H {
					lum[yy*W+xx] += e * w
				}
			}
			spread(1, 0, 7.0/16)
			spread(-1, 1, 3.0/16)
			spread(0, 1, 5.0/16)
			spread(1, 1, 1.0/16)
		}
	}
	dots := [4][2]int{{0x01, 0x08}, {0x02, 0x10}, {0x04, 0x20}, {0x40, 0x80}}
	var sb strings.Builder
	for cy := 0; cy < H/4; cy++ {
		for cx := 0; cx < cols; cx++ {
			c := 0
			for dy := 0; dy < 4; dy++ {
				for dx := 0; dx < 2; dx++ {
					if on[(cy*4+dy)*W+cx*2+dx] {
						c |= dots[dy][dx]
					}
				}
			}
			if c == 0 {
				sb.WriteRune(' ')
			} else {
				sb.WriteRune(rune(0x2800 + c))
			}
		}
		sb.WriteByte('\n')
	}
	return sb.String(), nil
}

func fail(msg string) {
	fmt.Fprintln(os.Stderr, "surfetch:", msg)
	os.Exit(1)
}

const usage = `surfetch — system fetch with random anime ASCII art

  surfetch                     show system info with a random art (or your pinned one)
  surfetch NAME                random art from your collection ~/.local/share/surfetch/arts/NAME/
  surfetch --change            choose which art to show, or "random"
  surfetch --add FILE          add art from a .txt file, or an image (png/jpg/gif -> braille)
      --name NAME              name for the new art
      --width N                image conversion width in characters (default 40)
      --invert                 invert image conversion (swap which pixels become dots)
      --dither                 dithering for photos/gradients (default: clean threshold)
      --to NAME                add it to collection NAME (a private folder of your own)
  surfetch --add               paste your own art in $EDITOR (or pipe it: cat art.txt | surfetch --add)
  surfetch --art NAME          show a specific art once
  surfetch --list              list arts (* = yours)
  surfetch --remove NAME       remove one of your arts
`

func main() {
	args := os.Args[1:]
	if len(args) == 0 {
		render(pickArt())
		return
	}
	switch args[0] {
	case "--change", "-c":
		cmdChange()
	case "--add", "-a":
		cmdAdd(args[1:])
	case "--art":
		if len(args) < 2 {
			fail("usage: surfetch --art NAME")
		}
		a, ok := loadArt(args[1])
		if !ok {
			fail("no art named " + args[1] + " (see surfetch --list)")
		}
		render(a)
	case "--preview-art": // used by --change
		if len(args) > 1 && args[1] == "random" {
			fmt.Println("\n  a random art every time")
			return
		}
		if len(args) > 1 {
			if a, ok := loadArt(args[1]); ok {
				render(a)
			}
		}
	case "--list", "-l":
		b, u := artNames()
		p := pinned()
		for _, n := range b {
			fmt.Printf("  %s%s\n", n, map[bool]string{true: "  (showing)"}[n == p])
		}
		for _, n := range u {
			fmt.Printf("* %s%s\n", n, map[bool]string{true: "  (showing)"}[n == p])
		}
		for _, c := range collections() {
			_, cu := catNames(c)
			fmt.Printf("\n%s (surfetch %s): %d arts\n", c, c, len(cu))
		}
		fmt.Println("\nmode:", p)
	case "--remove", "-r":
		if len(args) < 2 {
			fail("usage: surfetch --remove NAME")
		}
		if err := os.Remove(filepath.Join(userArts, args[1]+".txt")); err != nil {
			fail("no art of yours named " + args[1] + " (built-in arts can't be removed)")
		}
		if pinned() == args[1] {
			setPinned("random")
		}
		fmt.Println("removed", args[1])
	case "--help", "-h":
		fmt.Print(usage)
	default:
		if !strings.HasPrefix(args[0], "-") {
			if st, err := os.Stat(filepath.Join(userArts, args[0])); err == nil && st.IsDir() {
				render(pickFrom(args[0]))
				return
			}
		}
		fail("unknown option " + args[0] + "\n\n" + usage)
	}
}
