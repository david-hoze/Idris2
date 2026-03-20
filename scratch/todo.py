import sys
import time

tasks = []

def add_task(desc):
    tasks.append({"desc": desc, "done": False, "added": time.time()})

def list_tasks():
    if not tasks:
        print("No tasks")
        return
    for i, t in enumerate(tasks):
        status = "x" if t["done"] else " "
        print(f"  [{status}] {i}: {t['desc']}")

def complete_task(n):
    if 0 <= n < len(tasks):
        tasks[n]["done"] = True
        print(f"Completed: {tasks[n]['desc']}")
    else:
        print(f"Invalid task number: {n}")

def stats():
    total = len(tasks)
    done = sum(1 for t in tasks if t["done"])
    print(f"Total: {total}, Done: {done}, Pending: {total - done}")

def main():
    print("TODO App v1.0")
    while True:
        cmd = input("> ").strip()
        if cmd == "quit":
            break
        elif cmd == "list":
            list_tasks()
        elif cmd == "stats":
            stats()
        elif cmd.startswith("done "):
            try:
                complete_task(int(cmd[5:]))
            except ValueError:
                print("Usage: done <number>")
        elif cmd:
            add_task(cmd)
            print(f"Added: {cmd}")
        else:
            print("Commands: <text>, list, done <n>, stats, quit")

if __name__ == "__main__":
    main()
