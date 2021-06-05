#!env python3
import click
import os

def write_int(filename, value):
    f = open(filename, "w")
    f.write(str(value))
    f.close()

def read_int(file):
    line = open(file).readline()
    return int(line)

@click.command()
@click.option('-v',  default='/V1/num', help='file number of executions.')
def main(v):
    if not os.path.exists(v):
        print(f"{v} does not exist, creating ... ")
        os.mknod(v)
        print("And writing 0 to it ... ")
        write_int(v,1)

    num = read_int(v)
    print(f"The number of executions is {num}" )
    write_int(v, num+1)
    
if __name__ == '__main__':
    main()
