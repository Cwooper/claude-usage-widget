.pragma library

// `coarse` drops the second unit, for rings too small to fit "10h 42m" between
// the arc walls.
function duration(seconds, coarse) {
    if (!isFinite(seconds) || seconds <= 0) {
        return "now";
    }
    const days = Math.floor(seconds / 86400);
    const hours = Math.floor((seconds % 86400) / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);
    if (days > 0) {
        return coarse ? days + "d" : days + "d " + hours + "h";
    }
    if (hours > 0) {
        return coarse ? hours + "h" : hours + "h " + minutes + "m";
    }
    return minutes + "m";
}

// White labels wash out against the light end of the model ramp.
function textOn(fill) {
    const luminance = 0.299 * fill.r + 0.587 * fill.g + 0.114 * fill.b;
    return luminance > 0.6 ? "#1b1b1b" : "#ffffff";
}

function tokens(count) {
    if (!isFinite(count) || count <= 0) {
        return "0";
    }
    if (count >= 1e6) {
        return (count / 1e6).toFixed(1) + "M";
    }
    if (count >= 1e3) {
        return Math.round(count / 1e3) + "k";
    }
    return String(Math.round(count));
}
