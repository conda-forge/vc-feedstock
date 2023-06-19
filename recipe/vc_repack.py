import argparse
import os
import shutil
import string
import subprocess
import sys
import tempfile
import xml.dom.minidom
from glob import glob

# Requires m2-p7zip conda package on Windows
# If cross-building on Linux, requires p7zip installed

# All Microsoft CAB archives start with this signature
MS_CAB_HEADER = b"MSCF\0\0\0\0"

EXE_FILENAMES = {
    "win-arm64": "vc_redist.arm64.exe",
    "win-64": "vc_redist.x64.exe",
    "win-32": "vc_redist.x86.exe",
}


class Environment:
    # Read in conda build environment variables
    # This allows us to pass them round and refer to them as
    # e.recipe_dir, etc.
    items = [
        "RECIPE_DIR",
        "SRC_DIR",
        "PREFIX",
        "BUILD_PREFIX",
        "LIBRARY_BIN",
    ]

    def __init__(self):
        self.__attrs = {}
        for i in self.items:
            key = i.lower()
            value = os.environ.get(i, None)
            if value is None:
                if i == "LIBRARY_BIN":
                    value = os.path.join(os.environ.get("PREFIX"), "Library", "bin")
                else:
                    raise RuntimeError(f"{i} not set in environment")
            self.__attrs[key] = value

    def __getattr__(self, name):
        if name in self.__attrs:
            return self.__attrs[name]
        else:
            raise AttributeError


# This class and the subs() function balow are used for substituting
# variables in the activate.bat template
class AtTemplate(string.Template):
    delimiter = "@"


def get_cmake_plat(target_platform):
    if target_platform == "win-32":
        return "Win32"
    elif target_platform == "win-64":
        return "x64"
    elif target_platform == "win-arm64":
        return "ARM64"
    raise ValueError(f"Unknown target_platform {target_platform}")


def get_vcvarsbat(target_platform, host_platform):
    t = target_platform
    h = host_platform
    if h == "win-32" and t == "win-32":
        return "32"
    if h == "win-32" and t == "win-64":
        return "x86_amd64"
    if h == "win-32" and t == "win-arm64":
        return "x86_arm64"
    if h == "win-64" and t == "win-32":
        return "amd64_x86"
    if h == "win-64" and t == "win-64":
        return "64"
    if h == "win-64" and t == "win-arm64":
        return "amd64_arm64"
    if h == "win-arm64" and t == "win-32":
        return "arm64_x86"
    if h == "win-arm64" and t == "win-64":
        return "arm64_amd64"
    if h == "win-arm64" and t == "win-arm64":
        return "arm64"
    raise ValueError("Unknown target and host platform combo: "
        f"{(target_platform, host_platform)}")


def get_target_processor(target_platform):
    if target_platform == "win-32":
        return "x86"
    elif target_platform == "win-64":
        return "AMD64"
    elif target_platform == "win-arm64":
        return "ARM64"
    raise ValueError(f"Unknown target_platform {target_platform}")


def subs(line, args):
    t = AtTemplate(line)
    d = {
        "year": args.activate_year,
        "ver": args.activate_major,
        "target_platform": args.target_platform,
        "target_processor": get_target_processor(args.target_platform),
        "host_platform": args.host_platform,
        "vcvars_ver": args.activate_vcvars_ver,
        "ver_plus_one": str(int(args.activate_major)+1),
        "vcver_nodots": args.activate_vcver.replace(".", ""),
        "cmake_plat": get_cmake_plat(args.target_platform),
        "vcvarsbat": get_vcvarsbat(args.target_platform, args.host_platform),
    }
    return t.substitute(d)


def run(cmd):
    print(repr(cmd))
    proc = subprocess.run(cmd, check=True)
    if proc.returncode != 0:
        raise RuntimeError(f"Error running: {' '.join(cmd)}")


def split_self_extract_exe(exe_file, target_directory):
    # The self-extracting exe file contains two embedded CAB archives.
    # Split these out using a match against the known Microsoft CAB
    # header.  It's not ideal, but it works.
    with open(exe_file, "rb") as f:
        contents = f.read()
    splits = contents.split(MS_CAB_HEADER)
    fnames = []
    index = 0
    for s in splits[1:]:
        index += 1
        fname = f"cab{index:02}.cab"
        with open(os.path.join(target_directory, fname), "wb") as c:
            c.write(MS_CAB_HEADER)
            c.write(s)
        fnames.append(fname)
    return fnames


def unpack_cab(cabfile, tmpdir, env):
    cwd = None
    if sys.platform.startswith("win"):
        # Behold the ugliness of the hoops you have to go through
        # to execute 7z here.  It's a Cygwin executable.

        cwd = os.getcwd()
        # The DLLs needed for executing 7z are in Library\usr\bin,
        # relative to the prefix directory, so temporarily set the
        # current directory to contain them.
        os.chdir(os.path.join(env.prefix, "Library", "usr", "bin"))

        # The executable for 7z is not installed on the path either
        cmd = [
            os.path.join(env.prefix, "Library", "usr", "lib", "p7zip", "7z")
        ]

        # And because it's a Cygwin executable, the drive name is
        # specially encoded and filenames need to use Unix style paths
        # rather than DOS style ones.
        cabfile = cabfile.replace("C:", "/cygdrive/c").replace("\\", "/")
        tmpdir = tmpdir.replace("C:", "/cygdrive/c").replace("\\", "/")
    else:
        # It's so much simpler on Linux
        cmd = [os.path.join(env.build_prefix, "bin", "7z")]

    cmd.extend(["e", f"-o{tmpdir}", "-bd", cabfile])
    run(cmd)
    if cwd:
        os.chdir(cwd)


def decode_manifest(directory):
    # The first CAB file contains a manifest in the file "0" in XML
    # format.
    dom = xml.dom.minidom.parse(os.path.join(directory, "0"))

    # The version is contained in Registration.Version
    registration = dom.documentElement.getElementsByTagName("Registration")
    version = registration[0].attributes["Version"].value
    line = f"MSVC Runtimes version: {version}"
    print("*" * len(line))
    print(line)
    print("*" * len(line))
    print(flush=True)

    # The other files have generic names such as a0, a1, etc.  The
    # manifest gives us their true names.  The FilePath contains the
    # a0 type filename, the SourcePath the true filename.
    payloads = dom.documentElement.getElementsByTagName("Payload")

    # Find the licence file.
    licences = [
        x.attributes
        for x in payloads
        if "FilePath" in x.attributes
        and x.attributes["FilePath"].value.lower() == "license.rtf"
    ]
    if len(licences) == 0:
        raise RuntimeError("Found no licences in the manifest")
    elif len(licences) > 1:
        raise RuntimeError("Found more than one licence in the manfiest")

    # Find the files that are in the second CAB file. These have
    # helpful filenames of u0, u1, etc.
    containers = [x for x in payloads if "Container" in x.attributes]

    # The DLL files we want are in the second CAB file, with a name of
    # "packages\vcRuntimeMinimum_amd64\cab1.cab",
    # "packages\VC_Runtime_arm64\cab1.cab",
    # "packages\vcRuntimeMinimum_x86\cab1.cab" or similar
    runtimes = [
        i.attributes
        for i in containers
        if (lambda v: "vcRuntimeMinimum" in v and v.endswith(".cab"))(
            i.attributes["FilePath"].value
        )
    ]
    if len(runtimes) == 0:
        runtimes = [
            i.attributes
            for i in containers
            if (lambda v: "VC_Runtime" in v and v.endswith(".cab"))(
                i.attributes["FilePath"].value
            )
        ]
    if len(runtimes) == 0:
        raise RuntimeError("Found no matches in the manifest")
    elif len(runtimes) > 1:
        raise RuntimeError("Found more than one match in the manfiest")

    return dict(
        cabfile=runtimes[0]["SourcePath"].value,
        licence=licences[0]["SourcePath"].value,
        version=version,
    )


def fix_filename_and_copy(source, dest):
    cwd = os.getcwd()
    os.chdir(source)
    # as of VS 17.6, the artefact contains intermediate DLL extensions,
    # which get renamed correctly upon installation; do it manually
    dlls = glob("*.dll") + glob("*.dll_amd64") + glob("*.dll_arm64")
    for fname in dlls:
        print(f"Found DLL: {fname}")
        if fname.startswith("api_"):
            new_fname = fname.replace("_", "-")
            os.rename(fname, new_fname)
        elif fname.endswith(".dll_amd64") or fname.endswith(".dll_arm64"):
            # 10 == len(".dll_amd64") == len(".dll_arm64")
            new_fname = fname[:-10] + ".dll"
            os.rename(fname, new_fname)
        else:
            new_fname = fname
        shutil.copyfile(new_fname, os.path.join(dest, new_fname))
    os.chdir(cwd)

def unpack_exe(exe_filename, env, version):
    with tempfile.TemporaryDirectory() as tmpdir:
        cabs = split_self_extract_exe(exe_filename, tmpdir)
        # The first cab is the installer data
        # The second is the payload
        with tempfile.TemporaryDirectory() as cabdir1:
            unpack_cab(os.path.join(tmpdir, cabs[0]), cabdir1, env)
            payload = decode_manifest(cabdir1)
            if version is not None:
                short_version = ".".join(payload["version"].split(".")[:3])
                if version != short_version:
                    raise RuntimeError(
                        f"Wanted version {version}, found {short_version}"
                    )
            shutil.copyfile(
                os.path.join(cabdir1, payload["licence"]),
                os.path.join(env.src_dir, "LICENSE.RTF"),
            )

        with tempfile.TemporaryDirectory() as cabdir2:
            unpack_cab(os.path.join(tmpdir, cabs[1]), cabdir2, env)
            os.makedirs(env.library_bin)
            unpack_cab(
                os.path.join(cabdir2, payload["cabfile"]), env.library_bin, env
            )
        fix_filename_and_copy(env.library_bin, env.prefix)


def main():
    print("env", os.environ["PATH"])
    parser = argparse.ArgumentParser(
        description="Extract MSVC runtime package"
    )
    parser.add_argument(
        "--host-platform",
        help="host architecture (eg. win-64, win-32)",
        default="win-64",
    )
    parser.add_argument(
        "--target-platform",
        help="target architecture (eg. win-64, win-32)",
        default="win-64",
    )
    parser.add_argument(
        "--extract", help="install files to LIBRARY_BIN", action="store_true"
    )
    parser.add_argument(
        "--activate", help="install activate.bat", action="store_true"
    )
    parser.add_argument(
        "--version", help="Runtime version number", default=None,
    )
    parser.add_argument(
        "--activate-year", help="VS Version Year", default=None,
    )
    parser.add_argument(
        "--activate-vcver", help="VC Version", default=None,
    )
    parser.add_argument(
        "--activate-vcvars-ver", help="VC Version", default=None,
    )
    parser.add_argument(
        "--activate-major", help="VS Major Version", default=None,
    )
    # This is needed due to a limitation of conda build
    parser.add_argument(
        "dummy", nargs="*", help="Extra arguments which will be discarded"
    )
    args = parser.parse_args()

    if not (args.extract or args.activate):
        parser.print_help()
        sys.exit(1)

    try:
        env = Environment()
    except RuntimeError as e:
        print("Error:", e)
        print()
        print("This script expects to be run in a conda build environment")
        print("with these environment variables set:")
        print(" ", ", ".join(Environment.items))
        sys.exit(2)

    if args.extract:
        if args.target_platform in EXE_FILENAMES:
            exe_path = os.path.join(env.src_dir, EXE_FILENAMES[args.target_platform])
            if os.path.exists(exe_path):
                unpack_exe(exe_path, env, args.version)
            else:
                raise RuntimeError(f"{exe_path} not found")
        else:
            raise RuntimeError(f"Architecture {args.target_platform} not supported")
    elif args.activate:
        # Populate the activate.bat template, which is used to include
        # the Visual Studio tools into the conda environment.
        targetdir = os.path.join(env.prefix, "etc", "conda", "activate.d")
        os.makedirs(targetdir)
        with open(os.path.join(env.recipe_dir, "activate.bat"), "r") as r:
            with open(
                os.path.join(
                    targetdir, f"vs{args.activate_year}_compiler_vars.bat"
                ),
                "w",
            ) as w:
                for line in r:
                    w.write(subs(line, args))


if __name__ == "__main__":
    main()
