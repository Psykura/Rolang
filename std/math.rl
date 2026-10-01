import "range.rl"
// Standard library: mathematical utilities
//
// Available as free functions (abs_i32, min_i64, sqrt, sin, cos, ...)
// AND as extension methods on numeric values:
//   (-5).abs(), 3.min(7), 2.pow(10), 4.0.sqrt(), 0.5.sin()

// ---- constants ----

pub def pi() -> f64 { 3.14159265358979323846 }

// ===================================================================
//  Pure-Rolang floating-point math (no libm dependency)
//
//  Free functions:  math_sqrt(x)   math_sin(x)   math_cos(x)   math_atan2(y,x)
//  Extension methods on f64:  x.sqrt()   x.sin()   x.cos()
// ===================================================================

// sqrt via Newton's method
pub def math_sqrt(x: f64) -> f64 {
    if x <= 0.0 {
        return 0.0;
    }
    var guess: f64 = x;
    for i in 0..<20 {
        guess = (guess + x / guess) * 0.5;
    }
    return guess;
}

// sin via Taylor series with argument reduction to [-pi, pi]
pub def math_sin(x: f64) -> f64 {
    // reduce to [-pi, pi]
    var t: f64 = x;
    let two_pi: f64 = 6.283185307179586;
    let pi: f64 = 3.141592653589793;
    while t > pi {
        t = t - two_pi;
    }
    while t < -pi {
        t = t + two_pi;
    }
    // Taylor: sin(t) = t - t^3/3! + t^5/5! - t^7/7! + t^9/9! - t^11/11!
    let t2 = t * t;
    let t3 = t2 * t;
    let t5 = t3 * t2;
    let t7 = t5 * t2;
    let t9 = t7 * t2;
    let t11 = t9 * t2;
    return t - t3 / 6.0 + t5 / 120.0 - t7 / 5040.0 + t9 / 362880.0 - t11 / 39916800.0;
}

// cos via cos(x) = sin(pi/2 - x)
pub def math_cos(x: f64) -> f64 {
    let half_pi: f64 = 1.5707963267948966;
    return math_sin(half_pi - x);
}

// atan2 via atan approximation, then quadrant adjustment
// uses rational approximation: atan(z) ≈ z / (1 + 0.28*z^2) for |z| <= 1
// with refinement for accuracy
pub def math_atan2(y: f64, x: f64) -> f64 {
    let pi: f64 = 3.141592653589793;
    let half_pi: f64 = 1.5707963267948966;

    if x == 0.0 {
        if y > 0.0 { return half_pi; }
        if y < 0.0 { return -half_pi; }
        return 0.0;
    }

    var abs_y = y;
    if abs_y < 0.0 { abs_y = -abs_y; }
    var abs_x = x;
    if abs_x < 0.0 { abs_x = -abs_x; }

    // atan via Taylor series for |y/x| <= 1, else use pi/2 - atan(|x/y|)
    var z: f64;
    var complement: Bool;
    if abs_y <= abs_x {
        z = y / x;
        complement = false;
    } else {
        z = x / y;
        complement = true;
        if z < 0.0 { z = -z; }
    }

    // Taylor: atan(z) = z - z^3/3 + z^5/5 - z^7/7 + z^9/9 - z^11/11
    let abs_z = z;
    let z2 = z * z;
    let z3 = z2 * z;
    let z5 = z3 * z2;
    let z7 = z5 * z2;
    let z9 = z7 * z2;
    let z11 = z9 * z2;
    var atan_z = z - z3 / 3.0 + z5 / 5.0 - z7 / 7.0 + z9 / 9.0 - z11 / 11.0;

    if complement {
        if y > 0.0 {
            atan_z = half_pi - atan_z;
        } else {
            atan_z = -half_pi + atan_z;
        }
    } else {
        if x < 0.0 {
            if y >= 0.0 {
                atan_z = atan_z + pi;
            } else {
                atan_z = atan_z - pi;
            }
        }
    }

    return atan_z;
}

// ---- Free function wrappers (safe now that extension methods are excluded from exports) ----

pub def sqrt(x: f64) -> f64 {
    return math_sqrt(x);
}

pub def sin(x: f64) -> f64 {
    return math_sin(x);
}

pub def cos(x: f64) -> f64 {
    return math_cos(x);
}

pub def atan2(y: f64, x: f64) -> f64 {
    return math_atan2(y, x);
}

// ---- Extension methods on builtin numeric types ----

pub extension i32 {
    pub def abs() -> i32 {
        if self < 0 { return -self; }
        return self;
    }

    pub def min(other: i32) -> i32 {
        if self < other { return self; }
        return other;
    }

    pub def max(other: i32) -> i32 {
        if self > other { return self; }
        return other;
    }

    pub def pow(exp: i32) -> i32 {
        var result = 1;
        var e = exp;
        while e > 0 {
            result = result * self;
            e = e - 1;
        }
        return result;
    }

    pub def is_positive() -> Bool {
        return self > 0;
    }

    pub def is_negative() -> Bool {
        return self < 0;
    }

    pub def is_zero() -> Bool {
        return self == 0;
    }

    pub def clamp(low: i32, high: i32) -> i32 {
        if self < low { return low; }
        if self > high { return high; }
        return self;
    }
}

pub extension i64 {
    pub def abs() -> i64 {
        if self < 0 { return -self; }
        return self;
    }

    pub def min(other: i64) -> i64 {
        if self < other { return self; }
        return other;
    }

    pub def max(other: i64) -> i64 {
        if self > other { return self; }
        return other;
    }

    pub def is_positive() -> Bool {
        return self > 0;
    }

    pub def is_negative() -> Bool {
        return self < 0;
    }

    pub def is_zero() -> Bool {
        return self == 0;
    }
}

pub extension f64 {
    pub def sqrt() -> f64 {
        return math_sqrt(self);
    }

    pub def sin() -> f64 {
        return math_sin(self);
    }

    pub def cos() -> f64 {
        return math_cos(self);
    }

    pub def abs() -> f64 {
        if self < 0.0 { return -self; }
        return self;
    }

    pub def min(other: f64) -> f64 {
        if self < other { return self; }
        return other;
    }

    pub def max(other: f64) -> f64 {
        if self > other { return self; }
        return other;
    }
}

// ---- Free functions (for cross-module import compatibility) ----

pub def abs_i32(x: i32) -> i32 {
    return x.abs();
}

pub def abs_i64(x: i64) -> i64 {
    return x.abs();
}

pub def min_i32(a: i32, b: i32) -> i32 {
    return a.min(b);
}

pub def max_i32(a: i32, b: i32) -> i32 {
    return a.max(b);
}

pub def min_i64(a: i64, b: i64) -> i64 {
    return a.min(b);
}

pub def max_i64(a: i64, b: i64) -> i64 {
    return a.max(b);
}

pub def pow_i32(base: i32, exp: i32) -> i32 {
    return base.pow(exp);
}
