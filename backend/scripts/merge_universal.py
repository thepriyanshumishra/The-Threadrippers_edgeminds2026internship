import os
import sys
import subprocess
import shutil

def merge_dirs(src_arm64, src_x64, dst):
    if not os.path.exists(dst):
        os.makedirs(dst)
        
    for item in os.listdir(src_arm64):
        p_arm64 = os.path.join(src_arm64, item)
        p_x64 = os.path.join(src_x64, item)
        p_dst = os.path.join(dst, item)
        
        if os.path.isdir(p_arm64):
            if os.path.exists(p_x64):
                merge_dirs(p_arm64, p_x64, p_dst)
            else:
                shutil.copytree(p_arm64, p_dst)
        else:
            # It's a file. If it doesn't exist in the x64 side, just copy it.
            if not os.path.exists(p_x64):
                shutil.copy2(p_arm64, p_dst)
                continue
                
            # If both exist, check if it's a Mach-O compiled binary (e.g. executable or dylib)
            is_binary = p_arm64.endswith(('.dylib', '.so')) or item == 'kivo_backend'
            
            if is_binary:
                try:
                    # Run lipo -create to merge arm64 and x86_64 binaries into a universal binary
                    print(f"Creating universal binary: {item}")
                    subprocess.run(['lipo', '-create', '-output', p_dst, p_arm64, p_x64], check=True)
                except Exception as e:
                    print(f"Failed to lipo merge {item}, falling back to copy: {e}")
                    shutil.copy2(p_arm64, p_dst)
            else:
                # For non-binary assets, just copy the arm64 version
                shutil.copy2(p_arm64, p_dst)

if __name__ == '__main__':
    if len(sys.argv) < 4:
        print("Usage: python merge_universal.py <arm64_dir> <x64_dir> <dst_dir>")
        sys.exit(1)
        
    arm64_dir = sys.argv[1]
    x64_dir = sys.argv[2]
    dst_dir = sys.argv[3]
    
    print(f"Merging {arm64_dir} (Silicon) and {x64_dir} (Intel) into {dst_dir}")
    merge_dirs(arm64_dir, x64_dir, dst_dir)
    print("Universal merge completed successfully!")
