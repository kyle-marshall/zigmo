const std = @import("std");
const math = @import("math.zig");
const Vec2 = math.Vec2(f32);

// The following is a port of Stefan Gustavson's SimplexNoise implementation.
// some comments are copied from the original

// Original note from author:
// /* SimplexNoise1234, Simplex noise with true analytic
//  * derivative in 1D to 4D.
//  *
//  * Author: Stefan Gustavson, 2003-2005
//  * Contact: stefan.gustavson@liu.se
//  *
//  * This code was GPL licensed until February 2011.
//  * As the original author of this code, I hereby
//  * release it into the public domain.
//  * Please feel free to use it for whatever you want.
//  * Credit is appreciated where appropriate, and I also
//  * appreciate being told where this code finds any use,
//  * but you may do as you like.
//  */

const N: f32 = 2;
const F2: f32 = (@sqrt(N + 1) - 1) / N;
const G2: f32 = (3 - @sqrt(3.0)) / 6.0;

/// Permutation table. This is just a random jumble of all numbers 0-255,
/// repeated twice to avoid wrapping the index at 255 for each lookup.
const perm = [512]u8{ 151, 160, 137, 91, 90, 15, 131, 13, 201, 95, 96, 53, 194, 233, 7, 225, 140, 36, 103, 30, 69, 142, 8, 99, 37, 240, 21, 10, 23, 190, 6, 148, 247, 120, 234, 75, 0, 26, 197, 62, 94, 252, 219, 203, 117, 35, 11, 32, 57, 177, 33, 88, 237, 149, 56, 87, 174, 20, 125, 136, 171, 168, 68, 175, 74, 165, 71, 134, 139, 48, 27, 166, 77, 146, 158, 231, 83, 111, 229, 122, 60, 211, 133, 230, 220, 105, 92, 41, 55, 46, 245, 40, 244, 102, 143, 54, 65, 25, 63, 161, 1, 216, 80, 73, 209, 76, 132, 187, 208, 89, 18, 169, 200, 196, 135, 130, 116, 188, 159, 86, 164, 100, 109, 198, 173, 186, 3, 64, 52, 217, 226, 250, 124, 123, 5, 202, 38, 147, 118, 126, 255, 82, 85, 212, 207, 206, 59, 227, 47, 16, 58, 17, 182, 189, 28, 42, 223, 183, 170, 213, 119, 248, 152, 2, 44, 154, 163, 70, 221, 153, 101, 155, 167, 43, 172, 9, 129, 22, 39, 253, 19, 98, 108, 110, 79, 113, 224, 232, 178, 185, 112, 104, 218, 246, 97, 228, 251, 34, 242, 193, 238, 210, 144, 12, 191, 179, 162, 241, 81, 51, 145, 235, 249, 14, 239, 107, 49, 192, 214, 31, 181, 199, 106, 157, 184, 84, 204, 176, 115, 121, 50, 45, 127, 4, 150, 254, 138, 236, 205, 93, 222, 114, 67, 29, 24, 72, 243, 141, 128, 195, 78, 66, 215, 61, 156, 180, 151, 160, 137, 91, 90, 15, 131, 13, 201, 95, 96, 53, 194, 233, 7, 225, 140, 36, 103, 30, 69, 142, 8, 99, 37, 240, 21, 10, 23, 190, 6, 148, 247, 120, 234, 75, 0, 26, 197, 62, 94, 252, 219, 203, 117, 35, 11, 32, 57, 177, 33, 88, 237, 149, 56, 87, 174, 20, 125, 136, 171, 168, 68, 175, 74, 165, 71, 134, 139, 48, 27, 166, 77, 146, 158, 231, 83, 111, 229, 122, 60, 211, 133, 230, 220, 105, 92, 41, 55, 46, 245, 40, 244, 102, 143, 54, 65, 25, 63, 161, 1, 216, 80, 73, 209, 76, 132, 187, 208, 89, 18, 169, 200, 196, 135, 130, 116, 188, 159, 86, 164, 100, 109, 198, 173, 186, 3, 64, 52, 217, 226, 250, 124, 123, 5, 202, 38, 147, 118, 126, 255, 82, 85, 212, 207, 206, 59, 227, 47, 16, 58, 17, 182, 189, 28, 42, 223, 183, 170, 213, 119, 248, 152, 2, 44, 154, 163, 70, 221, 153, 101, 155, 167, 43, 172, 9, 129, 22, 39, 253, 19, 98, 108, 110, 79, 113, 224, 232, 178, 185, 112, 104, 218, 246, 97, 228, 251, 34, 242, 193, 238, 210, 144, 12, 191, 179, 162, 241, 81, 51, 145, 235, 249, 14, 239, 107, 49, 192, 214, 31, 181, 199, 106, 157, 184, 84, 204, 176, 115, 121, 50, 45, 127, 4, 150, 254, 138, 236, 205, 93, 222, 114, 67, 29, 24, 72, 243, 141, 128, 195, 78, 66, 215, 61, 156, 180 };

//---------------------------------------------------------------------

// Helper functions to compute gradients-dot-residualvectors (1D to 4D)
// Note that these generate gradients of more than unit length. To make
// a close match with the value range of classic Perlin noise, the final
// noise values need to be rescaled to fit nicely within [-1,1].
// (The simplex noise functions as such also have different scaling.)
// Note also that these noise functions are the most practical and useful
// signed version of Perlin noise. To return values according to the
// RenderMan specification from the SL noise() and pnoise() functions,
// the noise values need to be scaled and offset to [0,1], like this:
// float SLnoise = (noise(x,y,z) + 1.0) * 0.5;

fn grad2(hash: i32, x: f32, y: f32) f32 {
    // Convert low 3 bits of hash code
    const h = hash & 7;
    // into 8 simple gradient directions,
    const u = if (h < 4) x else y;
    const v = if (h < 4) y else x;
    // and compute the dot product with (x,y).
    const a = if ((h & 1) > 0) -u else u;
    const b = if ((h & 2) > 0) -v else v;
    return a + 2.0 * b;
}

pub fn snoise2(x: f32, y: f32) f32 {
    var n0: f32 = undefined;
    var n1: f32 = undefined;
    var n2: f32 = undefined;

    const s = (x + y) * F2;
    const xs = x + s;
    const ys = y + s;
    const i = @floor(xs);
    const j = @floor(ys);

    const t = (i + j) * G2;
    const x0 = i - t;
    const y0 = j - t;
    const x0p = x - x0;
    const y0p = y - y0;

    var ip: u8 = undefined;
    var jp: u8 = undefined;
    if (x0p > y0p) {
        ip = 1;
        jp = 0;
    } else {
        ip = 0;
        jp = 1;
    }

    const x1 = x0p - @intToFloat(f32, ip) + G2;
    const y1 = y0p - @intToFloat(f32, jp) + G2;
    const x2 = x0p - 1.0 + 2.0 * G2;
    const y2 = y0p - 1.0 + 2.0 * G2;

    const i_byte = @intCast(u16, (@floatToInt(i32, i) & 255));
    const j_byte = @intCast(u16, (@floatToInt(i32, j) & 255));

    // Calculate the contribution from the three corners
    var t0 = 0.5 - x0p * x0p - y0p * y0p;
    if (t0 < 0.0) {
        n0 = 0.0;
    } else {
        t0 *= t0;
        n0 = t0 * t0 * grad2(
            perm[i_byte + perm[j_byte]],
            x0p,
            y0p,
        );
    }

    var t1 = 0.5 - x1 * x1 - y1 * y1;
    if (t1 < 0.0) {
        n1 = 0.0;
    } else {
        t1 *= t1;
        n1 = t1 * t1 * grad2(
            perm[i_byte + ip + perm[j_byte + jp]],
            x1,
            y1,
        );
    }

    var t2 = 0.5 - x2 * x2 - y2 * y2;
    if (t2 < 0.0) {
        n2 = 0.0;
    } else {
        t2 *= t2;
        n2 = t2 * t2 * grad2(
            perm[i_byte + 1 + perm[j_byte + 1]],
            x2,
            y2,
        );
    }
    // Add contributions from each corner to get the final noise value.
    // The result is scaled to return values in the interval [-1,1].

    // WARNING! MAGIC NUMBERS:
    return 45.23 * (n0 + n1 + n2);
}
