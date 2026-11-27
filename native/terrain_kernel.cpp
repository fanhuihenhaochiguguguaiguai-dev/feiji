#include "gdextension_interface.h"

namespace {

double blend(double a, double b, double t) { return a + (b-a)*t; }
double bound(double a, double lo, double hi) { return a < lo ? lo : (a > hi ? hi : a); }
double abs_value(double v) { return v < 0 ? -v : v; }
int64_t ilower(double v) { const auto n=static_cast<int64_t>(v); return n > v ? n-1 : n; }
double smooth(double t) { t=bound(t,0,1); return t*t*(3-2*t); }
uint64_t mix_bits(uint64_t v) {
    v=(v^(v>>30))*0xbf58476d1ce4e5b9ULL;
    v=(v^(v>>27))*0x94d049bb133111ebULL;
    return v^(v>>31);
}
double hash(int64_t x,int64_t z,int64_t seed) {
    const auto h=mix_bits(uint64_t(x)*0x9e3779b97f4a7c15ULL^uint64_t(z)*0x85ebca77c2b2ae63ULL^uint64_t(seed));
    return double(h>>40)/16777215.0;
}
double noise(double x,double z,int64_t seed) {
    const int64_t i=ilower(x), j=ilower(z);
    const double u=smooth(x-i),v=smooth(z-j);
    return blend(blend(hash(i,j,seed),hash(i+1,j,seed),u),
                 blend(hash(i,j+1,seed),hash(i+1,j+1,seed),u),v);
}
double height_at(double x,double z,int64_t seed) {
    // Warped coastline and ridge directions. Channel incision is strongest on uplands.
    const double coast=noise(x/7900.,z/6300.,seed+11)*.67+noise(x/4100.,z/4300.,seed+43)*.33;
    const double warp_x=(noise(x/2700.,z/3100.,seed+99)-.5)*1390;
    const double warp_z=(noise(x/2900.,z/2400.,seed+87)-.5)*1160;
    const double u=(x+warp_x)*.78+(z+warp_z)*.624;
    const double v=-(x+warp_x)*.624+(z+warp_z)*.78;
    const double belt=smooth((coast-.37)/.25);
    const double ridge=1-abs_value(noise(u/1020.,v/2940.,seed+41)*2-1);
    const double rib=1-abs_value(noise(u/310.,v/770.,seed+45)*2-1);
    const double runnel=1-abs_value(noise(u/415.,v/1050.,seed+71)*2-1);
    const double terrace=noise(u/87.,v/156.,seed+23)-.5;
    const double incision=(1-smooth((runnel-.05)/.34))*(.6+.4*ridge);
    const double climate=(seed==704?1.34:1.0);
    return (coast-.435)*920+climate*belt*(ridge*ridge*ridge*755+rib*rib*113-incision*150+terrace*27);
}
double base_height(double x,double z,int64_t seed) {
    const double pad=(1.0-smooth((abs_value(x+340)-36.0)/220.0))*(1.0-smooth((abs_value(z-350)-443.0)/305.0));
    return blend(height_at(x,z,seed),26.0,pad);
}

constexpr double erosion_spacing = 6.0;
constexpr int relief_side = 1025;
constexpr double relief_size = 24576.0;
constexpr double relief_x = -6250.0;
constexpr double relief_z = -6200.0;
int16_t relief[2][relief_side * relief_side];
bool has_relief[2]{};
uint8_t alpine_ground[relief_side * relief_side];
bool has_alpine_ground = false;

int field_for(int64_t seed) { return seed == 413 ? 0 : (seed == 704 ? 1 : -1); }

double relief_mask(double x, double z, int field) {
    if (field < 0 || !has_relief[field]) return 0.0;
    const double local_x = x - relief_x;
    const double local_z = z - relief_z;
    double weight = smooth(local_x / 2100.0) * smooth((relief_size-local_x) / 2100.0)
        * smooth(local_z / 2100.0) * smooth((relief_size-local_z) / 2100.0);
    // Leave the existing runway and its climb-out corridor at their authored grade.
    const double dx = x + 340.0, dz = z - 350.0;
    return weight * smooth((dx*dx + dz*dz - 3700.0*3700.0) / (4900.0*4900.0 - 3700.0*3700.0));
}

double relief_tangent(int before, int at, int after) {
    const int left = at - before, right = after - at;
    if (left > 0 && right > 0) return left < right ? left : right;
    if (left < 0 && right < 0) return left > right ? left : right;
    return 0.0;
}

double relief_sample(double x, double z, int field) {
    constexpr int last = relief_side - 1;
    x = bound((x-relief_x) * last / relief_size, 0, last);
    z = bound((z-relief_z) * last / relief_size, 0, last);
    const int a = x == last ? last - 1 : static_cast<int>(x);
    const int b = z == last ? last - 1 : static_cast<int>(z);
    const double u = x-a, v = z-b;
    const int16_t *row = relief[field] + b * relief_side + a;
    if (u == 0.0 && v == 0.0) return 0.25 * row[0];
    const int west = a > 0 ? -1 : 0, east = a + 1 < last ? 2 : 1;
    const int north = b > 0 ? -relief_side : 0, south = b + 1 < last ? 2 * relief_side : relief_side;
    const double hu = u*u*(3-2*u), hv = v*v*(3-2*v);
    const double ux0 = u*(1-u)*(1-u), ux1 = -u*u*(1-u);
    const double vz0 = v*(1-v)*(1-v), vz1 = -v*v*(1-v);
    const int16_t *near = row + relief_side;
    const double top = blend(row[0], row[1], hu)
        + ux0 * relief_tangent(row[west], row[0], row[1])
        + ux1 * relief_tangent(row[0], row[1], row[east]);
    const double bottom = blend(near[0], near[1], hu)
        + ux0 * relief_tangent(near[west], near[0], near[1])
        + ux1 * relief_tangent(near[0], near[1], near[east]);
    const double dz0 = blend(relief_tangent(row[north], row[0], near[0]),
        relief_tangent(row[north+1], row[1], near[1]), hu);
    const double dz1 = blend(relief_tangent(row[0], near[0], row[south]),
        relief_tangent(row[1], near[1], row[south+1]), hu);
    // Adjacent cells share node tangents and zero mixed derivatives. The limited tangents
    // keep the bicubic Bezier control points within the four measured corner elevations.
    return 0.25 * (blend(top, bottom, hv) + vz0 * dz0 + vz1 * dz1);
}

double thermal_flux(double difference) {
    const double angle_limit = erosion_spacing * 0.73;
    const double moving_height = bound(abs_value(difference) - angle_limit, 0.0, 7.0);
    return difference < 0.0 ? -moving_height * 0.145 : moving_height * 0.145;
}

double transported_height(double centre, double north, double south, double east, double west) {
    return centre + thermal_flux(north-centre) + thermal_flux(south-centre)
        + thermal_flux(east-centre) + thermal_flux(west-centre);
}

double terrain_height(double x,double z,int64_t seed) {
    const int field = field_for(seed);
    const double mask = relief_mask(x,z,field);
    if (mask >= 1.0) return relief_sample(x,z,field);
    const double original = transported_height(base_height(x,z,seed),
        base_height(x,z-erosion_spacing,seed), base_height(x,z+erosion_spacing,seed),
        base_height(x+erosion_spacing,z,seed), base_height(x-erosion_spacing,z,seed));
    return mask > 0.0 ? blend(original, relief_sample(x,z,field), mask) : original;
}

void tile_heights(float* output, int64_t size, double x, double z, double step, int64_t seed) {
    const int field = field_for(seed);
    if (field >= 0 && has_relief[field] && x > relief_x && z > relief_z &&
        x + (size-1)*step < relief_x + relief_size && z + (size-1)*step < relief_z + relief_size &&
        relief_mask(x,z,field) == 1.0 && relief_mask(x+(size-1)*step,z+(size-1)*step,field) == 1.0 &&
        (x > 4600.0 || z > 5300.0 || z+(size-1)*step < -4600.0)) {
        for (int64_t y=0; y<size; ++y)
            for (int64_t i=0; i<size; ++i)
                output[y*size+i] = static_cast<float>(relief_sample(x+i*step,z+y*step,field));
        return;
    }
    if (step != erosion_spacing) {
        for (int64_t y=0; y<size; ++y)
            for (int64_t i=0; i<size; ++i)
                output[y*size+i]=static_cast<float>(terrain_height(x+i*step,z+y*step,seed));
        return;
    }

    // A one-vertex halo gives neighbouring tiles the same boundary transport.
    double strip[3][514];
    const auto fill_row = [=](double* row, int64_t offset) {
        for (int64_t i=0; i<size+2; ++i)
            row[i]=base_height(x+(i-1)*step,z+offset*step,seed);
    };
    fill_row(strip[0],-1);
    fill_row(strip[1],0);
    for (int64_t y=0; y<size; ++y) {
        const auto north=y%3;
        const auto centre=(y+1)%3;
        const auto south=(y+2)%3;
        fill_row(strip[south],y+1);
        for (int64_t i=1; i<=size; ++i) {
            const double px = x+(i-1)*step, pz = z+y*step;
            const double mask = relief_mask(px,pz,field);
            const double h = transported_height(strip[centre][i],
                strip[north][i],strip[south][i],strip[centre][i+1],strip[centre][i-1]);
            output[y*size+i-1] = static_cast<float>(mask > 0.0 ? blend(h,relief_sample(px,pz,field),mask) : h);
        }
    }
}

GDExtensionClassLibraryPtr library;
GDExtensionInterfaceGetProcAddress proc;
GDExtensionInterfaceStringNameNewWithUtf8Chars name_new;
GDExtensionInterfaceVariantGetPtrDestructor get_dtor;
GDExtensionInterfaceVariantDestroy destroy;
GDExtensionInterfaceVariantConstruct construct;
GDExtensionInterfaceVariantCall invoke;
GDExtensionInterfacePackedFloat32ArrayOperatorIndex float_index;
GDExtensionInterfacePackedFloat32ArrayOperatorIndexConst float_read;
GDExtensionInterfacePackedByteArrayOperatorIndexConst byte_index;
GDExtensionTypeFromVariantConstructorFunc to_bytes;
GDExtensionVariantFromTypeConstructorFunc from_int,from_float,from_array;
GDExtensionTypeFromVariantConstructorFunc to_float,to_int,to_array;
struct alignas(16) Slot { unsigned char opaque[64]; };
Slot klass, base, sample_name, tile_name, resize_name, relief_name, decode_name, alpine_name, snow_tile_name, size_name;

template<class T> T fn(const char *name) { return reinterpret_cast<T>(proc(name)); }
int64_t integer(GDExtensionConstVariantPtr v) { int64_t n=0; to_int(&n,const_cast<void *>(v)); return n; }
double number(GDExtensionConstVariantPtr v) { double n=0; to_float(&n,const_cast<void *>(v)); return n; }

int64_t packed_size(GDExtensionConstVariantPtr value) {
    Slot ret;
    GDExtensionCallError result{};
    invoke(const_cast<void *>(value), &size_name, nullptr, 0, &ret, &result);
    const int64_t count = result.error == GDEXTENSION_CALL_OK ? integer(&ret) : 0;
    destroy(&ret);
    return count;
}

void load_alpine_ground(void *, GDExtensionClassInstancePtr, const GDExtensionConstVariantPtr *args,
                        GDExtensionInt nargs, GDExtensionVariantPtr, GDExtensionCallError *err) {
    if (nargs != 1 || packed_size(args[0]) != relief_side * relief_side) {
        err->error = GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT;
        return;
    }
    if (!has_alpine_ground) {
        Slot bytes;
        to_bytes(&bytes, const_cast<void *>(args[0]));
        const uint8_t *source = byte_index(&bytes, 0);
        for (int i = 0; i < relief_side * relief_side; ++i) alpine_ground[i] = source[i];
        get_dtor(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY)(&bytes);
        has_alpine_ground = true;
    }
    err->error = GDEXTENSION_CALL_OK;
}

double alpine_cover(double x, double z, double height, double grade) {
    const double fresh = smooth((height - 450.0) / 310.0) * (1.0 - .85 * smooth((grade - .38) / .62));
    const double gx = (x + 6144.0) / 24.0;
    const double gz = (z + 6144.0) / 24.0;
    if (!has_alpine_ground || gx <= 0 || gz <= 0 || gx >= 1024 || gz >= 1024) return fresh;
    const int i = int(gx);
    const int j = int(gz);
    const uint8_t *row = alpine_ground + j * relief_side + i;
    const double survey = blend(blend(row[0], row[1], gx - i),
        blend(row[relief_side], row[relief_side + 1], gx - i), gz - j) / 255.0;
    return blend(fresh, survey, relief_mask(x, z, 1)) * smooth((height - 300.0) / 120.0);
}

void load_relief(void *,GDExtensionClassInstancePtr,const GDExtensionConstVariantPtr *args,
                 GDExtensionInt nargs,GDExtensionVariantPtr,GDExtensionCallError *err) {
    const int field = nargs == 3 ? field_for(integer(args[2])) : -1;
    if (field < 0 || integer(args[1]) != relief_side*relief_side*2) {
        err->error = GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT;
        return;
    }
    if (!has_relief[field]) {
        Slot bytes;
        to_bytes(&bytes,const_cast<void *>(args[0]));
        const auto *src = byte_index(&bytes,0);
        for (int i=0; i<relief_side*relief_side; ++i)
            relief[field][i] = static_cast<int16_t>(src[i*2] | uint16_t(src[i*2+1]) << 8);
        get_dtor(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY)(&bytes);
        has_relief[field] = true;
    }
    err->error = GDEXTENSION_CALL_OK;
}

void sample(void *,GDExtensionClassInstancePtr,const GDExtensionConstVariantPtr *args,
            GDExtensionInt nargs,GDExtensionVariantPtr out,GDExtensionCallError *err) {
    const double h=nargs==3?terrain_height(number(args[0]),number(args[1]),integer(args[2])):0.0;
    destroy(out);
    from_float(out,const_cast<double*>(&h));
    err->error=nargs==3?GDEXTENSION_CALL_OK:GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS;
}
template<class Fill>
void height_array(int64_t count, GDExtensionVariantPtr out, GDExtensionCallError *err, Fill fill) {
    Slot values,n,ret,array;
    GDExtensionCallError result{};
    construct(GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY,&values,nullptr,0,&result);
    from_int(&n,&count);
    GDExtensionConstVariantPtr resize_args[]{&n};
    invoke(&values,&resize_name,resize_args,1,&ret,&result);
    destroy(&ret);destroy(&n);
    if(result.error!=GDEXTENSION_CALL_OK){destroy(&values);*err=result;return;}
    to_array(&array,&values);
    fill(float_index(&array,0));
    destroy(out);
    from_array(out,&array);
    get_dtor(GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY)(&array);
    destroy(&values);
    err->error=GDEXTENSION_CALL_OK;
}
void tile(void *,GDExtensionClassInstancePtr,const GDExtensionConstVariantPtr *args,
          GDExtensionInt nargs,GDExtensionVariantPtr out,GDExtensionCallError *err) {
    if (nargs!=5) { err->error=GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS; return; }
    const double x=number(args[0]),z=number(args[1]),step=number(args[3]);
    const int64_t size=integer(args[2]),seed=integer(args[4]);
    if(size<1||size>512||step<=0) { err->error=GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT; return; }
    height_array(size*size, out, err, [=](float *data) { tile_heights(data, size, x, z, step, seed); });
}

void snow_control_tile(void *, GDExtensionClassInstancePtr, const GDExtensionConstVariantPtr *args,
                       GDExtensionInt nargs, GDExtensionVariantPtr out, GDExtensionCallError *err) {
    const int64_t side = nargs == 5 ? integer(args[2]) : 0;
    if (side < 2 || side > 512 || packed_size(args[4]) != side * side || number(args[3]) <= 0) {
        err->error = GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT;
        return;
    }
    const double x = number(args[0]), z = number(args[1]), step = number(args[3]);
    Slot input;
    to_array(&input, const_cast<void *>(args[4]));
    const float *elevations = float_read(&input, 0);
    height_array(side * side, out, err, [=](float *controls) {
        for (int64_t row = 0; row < side; ++row) {
            for (int64_t col = 0; col < side; ++col) {
                const int64_t index = row * side + col;
                const double dx = (elevations[index + (col + 1 < side)] -
                    elevations[index - (col > 0)]) / (step * (1 + (col > 0 && col + 1 < side)));
                const double dz = (elevations[index + (row + 1 < side ? side : 0)] -
                    elevations[index - (row > 0 ? side : 0)]) / (step * (1 + (row > 0 && row + 1 < side)));
                const double coverage = alpine_cover(x + col * step, z + row * step,
                    elevations[index], __builtin_sqrt(dx * dx + dz * dz));
                // Terrain3D 1.1 control format: base rock (1), overlay snow (0), blend, autopaint clear.
                const uint32_t control = (1u << 27) | (uint32_t(coverage * 255.0 + .5) << 14);
                __builtin_memcpy(controls + index, &control, sizeof(control));
            }
        }
    });
    get_dtor(GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY)(&input);
}

void decode_tile(void *, GDExtensionClassInstancePtr, const GDExtensionConstVariantPtr *args,
                 GDExtensionInt nargs, GDExtensionVariantPtr out, GDExtensionCallError *err) {
    const int64_t size = nargs == 3 ? integer(args[1]) : 0;
    if (size < 1 || size > 512 || integer(args[2]) != 4 + size * size * 2) {
        err->error = GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT;
        return;
    }
    Slot encoded;
    to_bytes(&encoded, const_cast<void *>(args[0]));
    const uint8_t *data = byte_index(&encoded, 0);
    height_array(size * size, out, err, [=](float *heights) {
        const uint32_t first = data[0] | (uint32_t(data[1]) << 8) | (uint32_t(data[2]) << 16) | (uint32_t(data[3]) << 24);
        int64_t previous[512];
        const uint8_t *next = data + 4;
        for (int64_t y = 0; y < size; ++y) {
            int64_t west = 0;
            int64_t northwest = 0;
            for (int64_t x = 0; x < size; ++x) {
                const int64_t north = y == 0 ? 0 : previous[x];
                const auto delta = static_cast<int16_t>(next[0] | uint16_t(next[1]) << 8);
                next += 2;
                const int64_t predictor = y == 0 && x == 0 ? static_cast<int32_t>(first) : west + north - northwest;
                const int64_t elevation = predictor + delta;
                heights[y * size + x] = static_cast<float>(elevation) * 0.0625f;
                previous[x] = west = elevation;
                northwest = north;
            }
        }
    });
    get_dtor(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY)(&encoded);
}
void bind(Slot& name,GDExtensionClassMethodCall function,GDExtensionVariantType result_type,
          const GDExtensionVariantType *types,const char **labels,uint32_t count) {
    GDExtensionClassMethodInfo info{};
    GDExtensionPropertyInfo arguments[5]{},result{};
    GDExtensionClassMethodArgumentMetadata metadata[5]{};
    Slot argument_names[5],empty,hint;
    name_new(&empty,"");
    fn<GDExtensionInterfaceStringNewWithUtf8Chars>("string_new_with_utf8_chars")(&hint,"");
    for(uint32_t i=0;i<count;i++){
        name_new(&argument_names[i],labels[i]);
        arguments[i].type=types[i];arguments[i].name=&argument_names[i];arguments[i].class_name=&empty;
        arguments[i].hint_string=&hint;arguments[i].usage=6;
    }
    result.type=result_type;result.name=&empty;result.class_name=&empty;result.hint_string=&hint;result.usage=6;
    info.name=&name;info.call_func=function;info.method_flags=GDEXTENSION_METHOD_FLAG_NORMAL|GDEXTENSION_METHOD_FLAG_STATIC;
    info.has_return_value=result_type!=GDEXTENSION_VARIANT_TYPE_NIL;info.return_value_info=&result;
    info.argument_count=count;info.arguments_info=arguments;info.arguments_metadata=metadata;
    fn<GDExtensionInterfaceClassdbRegisterExtensionClassMethod>("classdb_register_extension_class_method")(library,&klass,&info);
    for(uint32_t i=0;i<count;i++)get_dtor(GDEXTENSION_VARIANT_TYPE_STRING_NAME)(&argument_names[i]);
    get_dtor(GDEXTENSION_VARIANT_TYPE_STRING_NAME)(&empty);
    get_dtor(GDEXTENSION_VARIANT_TYPE_STRING)(&hint);
}
void initialize(void *,GDExtensionInitializationLevel level) {
    if(level!=GDEXTENSION_INITIALIZATION_SCENE)return;
    auto from=fn<GDExtensionInterfaceGetVariantFromTypeConstructor>("get_variant_from_type_constructor");
    auto to=fn<GDExtensionInterfaceGetVariantToTypeConstructor>("get_variant_to_type_constructor");
    from_int=from(GDEXTENSION_VARIANT_TYPE_INT);from_float=from(GDEXTENSION_VARIANT_TYPE_FLOAT);
    from_array=from(GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY);
    to_int=to(GDEXTENSION_VARIANT_TYPE_INT);to_float=to(GDEXTENSION_VARIANT_TYPE_FLOAT);
    to_array=to(GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY);
    to_bytes=to(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
    name_new=fn<GDExtensionInterfaceStringNameNewWithUtf8Chars>("string_name_new_with_utf8_chars");
    destroy=fn<GDExtensionInterfaceVariantDestroy>("variant_destroy");
    construct=fn<GDExtensionInterfaceVariantConstruct>("variant_construct");
    invoke=fn<GDExtensionInterfaceVariantCall>("variant_call");
    get_dtor=fn<GDExtensionInterfaceVariantGetPtrDestructor>("variant_get_ptr_destructor");
    float_index=fn<GDExtensionInterfacePackedFloat32ArrayOperatorIndex>("packed_float32_array_operator_index");
    float_read=fn<GDExtensionInterfacePackedFloat32ArrayOperatorIndexConst>("packed_float32_array_operator_index_const");
    byte_index=fn<GDExtensionInterfacePackedByteArrayOperatorIndexConst>("packed_byte_array_operator_index_const");
    name_new(&klass,"SkyTerrainKernel");name_new(&base,"RefCounted");name_new(&sample_name,"height_m");
    name_new(&tile_name,"height_tile");name_new(&resize_name,"resize");
    name_new(&relief_name,"load_relief");
    name_new(&decode_name,"decode_tile");
    name_new(&size_name,"size");
    name_new(&alpine_name,"load_alpine_ground");
    name_new(&snow_tile_name,"snow_control_tile");
    GDExtensionClassCreationInfo6 ci{};
    ci.is_abstract=true;ci.is_exposed=true;
    ci.free_instance_func=[](void *,GDExtensionClassInstancePtr){};
    fn<GDExtensionInterfaceClassdbRegisterExtensionClass6>("classdb_register_extension_class6")(library,&klass,&base,&ci);
    const GDExtensionVariantType sample_args[]{GDEXTENSION_VARIANT_TYPE_FLOAT,GDEXTENSION_VARIANT_TYPE_FLOAT,GDEXTENSION_VARIANT_TYPE_INT};
    const GDExtensionVariantType tile_args[]{GDEXTENSION_VARIANT_TYPE_FLOAT,GDEXTENSION_VARIANT_TYPE_FLOAT,GDEXTENSION_VARIANT_TYPE_INT,GDEXTENSION_VARIANT_TYPE_FLOAT,GDEXTENSION_VARIANT_TYPE_INT};
    const char *sample_labels[]{"x","z","seed"};
    const char *tile_labels[]{"x","z","size","step","seed"};
    bind(sample_name,sample,GDEXTENSION_VARIANT_TYPE_FLOAT,sample_args,sample_labels,3);
    bind(tile_name,tile,GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY,tile_args,tile_labels,5);
    const GDExtensionVariantType relief_args[]{GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY,GDEXTENSION_VARIANT_TYPE_INT,GDEXTENSION_VARIANT_TYPE_INT};
    const char *relief_labels[]{"elevations","byte_count","seed"};
    bind(relief_name,load_relief,GDEXTENSION_VARIANT_TYPE_NIL,relief_args,relief_labels,3);
    const char *decode_labels[]{"sample_residuals","side","byte_count"};
    bind(decode_name,decode_tile,GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY,relief_args,decode_labels,3);
    const char *alpine_labels[]{"accumulation"};
    bind(alpine_name,load_alpine_ground,GDEXTENSION_VARIANT_TYPE_NIL,relief_args,alpine_labels,1);
    const GDExtensionVariantType snow_args[]{GDEXTENSION_VARIANT_TYPE_FLOAT,GDEXTENSION_VARIANT_TYPE_FLOAT,
        GDEXTENSION_VARIANT_TYPE_INT,GDEXTENSION_VARIANT_TYPE_FLOAT,GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY};
    const char *snow_labels[]{"x","z","side","step","elevations"};
    bind(snow_tile_name,snow_control_tile,GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY,snow_args,snow_labels,5);
}
void deinitialize(void *,GDExtensionInitializationLevel level) {
    if(level!=GDEXTENSION_INITIALIZATION_SCENE)return;
    fn<GDExtensionInterfaceClassdbUnregisterExtensionClass>("classdb_unregister_extension_class")(library,&klass);
    const auto dtor=get_dtor(GDEXTENSION_VARIANT_TYPE_STRING_NAME);
    dtor(&snow_tile_name);dtor(&alpine_name);dtor(&size_name);
    dtor(&decode_name);dtor(&relief_name);
    dtor(&resize_name);dtor(&tile_name);dtor(&sample_name);dtor(&base);dtor(&klass);
}
}
extern "C" __attribute__((visibility("default")))
GDExtensionBool skyblade_terrain_init(GDExtensionInterfaceGetProcAddress get,GDExtensionClassLibraryPtr lib,GDExtensionInitialization *init) {
    proc=get;library=lib;init->minimum_initialization_level=GDEXTENSION_INITIALIZATION_SCENE;
    init->initialize=initialize;init->deinitialize=deinitialize;init->userdata=nullptr;return true;
}
