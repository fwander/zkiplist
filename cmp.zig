pub fn eq(a: anytype, b: @TypeOf(a)) bool {
    const T = @TypeOf(a);

    switch (@typeInfo(T)) {
        .Int, .ComptimeInt, .Float, .ComptimeFloat => {
            return a == b;
        },
        .Struct => {
            if (!@hasDecl(T, "eq")) {
                @compileError("provide an 'eq' impl for your struct: " ++ @typeName(T));
            }
            return T.eq(a, b);
        },
        .Array => {
            for (a, 0..) |_, i| {
                if (!eq(a[i], b[i])) return false;
            }
            return true;
        },
        .Vector => {
            var i: usize = 0;
            if (a.len != b.len) {
                return false;
            }
            while (i < a.len) : (i += 1) {
                if (!eq(a[i], b[i])) return false;
            }
            return true;
        },
        .Pointer => {
            switch (a.size) {
                .One => return eq(*a, *b),
                .Many, .Slice => {
                    for (a, 0..) |_, i| {
                        if (!eq(a[i], b[i])) return false;
                    }
                    return true;
                },
                .C => @compileError("Can't compare c style pointers"),
            }
        },
        else => @compileError("eq is not implemented for " ++ T),
    }
}

pub fn lt(a: anytype, b: @TypeOf(a)) bool {
    const T = @TypeOf(a);

    switch (@typeInfo(T)) {
        .Int, .ComptimeInt, .Float, .ComptimeFloat => {
            return a < b;
        },
        .Struct => {
            if (!@hasDecl(T, "lt")) {
                @compileError("provide an 'lt' impl for your struct: " ++ @typeName(T));
            }
            return T.eq(a, b);
        },
        .Array => {
            for (a, 0..) |_, i| {
                if (!lt(a[i], b[i])) return false;
            }
            return true;
        },
        .Vector => {
            var i: usize = 0;

            while (i < a.len) : (i += 1) {
                if (lt(b[i], a[i])) return false;
            }

            if (a.len < b.len) {
                return true;
            }

            return false;
        },
        .Pointer => {
            switch (a.size) {
                .One => return eq(*a, *b),
                .Many, .Slice => {
                    for (a, 0..) |_, i| {
                        if (lt(b[i], a[i])) return false;
                    }
                    return true;
                },
                .C => @compileError("Can't compare c style pointers"),
            }
        },
        else => @compileError("eq is not implemented for " ++ T),
    }
}

pub fn gt(a: anytype, b: @TypeOf(a)) bool {
    return !lt(a, b) and !eq(a, b);
}
