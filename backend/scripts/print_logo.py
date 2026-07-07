# backend/scripts/print_logo.py
# Purpose: Prints the compact, high-fidelity Kivo Workspace branding logo (4 teal squares + crisp text) 
# to guarantee a professional, non-distorted appearance in the terminal.

def print_kivo_logo():
    # Colors matching Kivo branding:
    # Teal/Cyan: #00CBA9 -> RGB(0, 203, 169)
    # Bright White: RGB(255, 255, 255)
    TEAL = "\033[38;2;0;203;169m"
    WHITE = "\033[1;37m"
    GRAY = "\033[0;90m"
    RESET = "\033[0m"

    logo_lines = [
        f"  {TEAL}▄▄▄▄   ▄▄▄▄{RESET}",
        f"  {TEAL}████   ████{RESET}",
        f"  {TEAL}▀▀▀▀   ▀▀▀▀{RESET}      {WHITE}K I V O   W O R K S P A C E{RESET}",
        f"  {TEAL}▄▄▄▄   ▄▄▄▄{RESET}      {GRAY}Edge Intelligence Platform{RESET}",
        f"  {TEAL}████   ████{RESET}",
        f"  {TEAL}▀▀▀▀   ▀▀▀▀{RESET}"
    ]

    for line in logo_lines:
        print(line)

if __name__ == "__main__":
    print_kivo_logo()
