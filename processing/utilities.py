
'''
Description: Utility module for espa-processing.

License: NASA Open Source Agreement 1.3
'''

import os
import errno
import datetime
import commands
import random


import settings


def date_from_year_doy(year, doy):
    '''Returns a python date object given a year and day of year'''

    d = datetime.date(int(year), 1, 1) + datetime.timedelta(int(doy) - 1)

    if int(d.year) != int(year):
        raise Exception("doy [%s] must fall within the specified year [%s]" %
                        (doy, year))
    else:
        return d


def execute_cmd(cmd):
    """Execute a system command line

    Args:
        cmd (str): The command line to execute.

    Returns:
        output (str): The stdout and/or stderr from the executed command.

    Raises:
        Exception(message)
    """

    output = ''
    (status, output) = commands.getstatusoutput(cmd)

    message = ''
    if status < 0:
        message = 'Application terminated by signal [{0}]'.format(cmd)

    if status != 0:
        message = 'Application failed to execute [{0}]'.format(cmd)

    if os.WEXITSTATUS(status) != 0:
        message = ('Application [{0}] returned error code [{1}]' \
                   .format(cmd, os.WEXITSTATUS(status)))

    if len(message) > 0:
        if len(output) > 0:
            # Add the output to the exception message
            message = ' Stdout/Stderr is: '.join([message, output])
        raise Exception(message)

    return output


def get_cache_hostname():
    '''
    Description:
      Poor mans load balancer for accessing the online cache over the private
      network
    '''

    host_list = settings.ESPA_CACHE_HOST_LIST

    def check_host_status(hostname):
        cmd = "ping -q -c 1 %s" % hostname

        try:
            execute_cmd(cmd)
        except Exception:
            return -1
        return 0

    def get_hostname():
        hostname = random.choice(host_list)
        if check_host_status(hostname) == 0:
            return hostname
        else:
            for x in host_list:
                if x == hostname:
                    host_list.remove(x)
            if len(host_list) > 0:
                return get_hostname()
            else:
                raise Exception("No online cache hosts available...")

    return get_hostname()


def create_directory(directory):
    '''
    Description:
        Create the specified directory with some error checking.

    Parameters:
        directory - The full path to create.
    '''

    # Create/Make sure the directory exists
    try:
        os.makedirs(directory, mode=0755)
    except OSError as ose:
        if ose.errno == errno.EEXIST and os.path.isdir(directory):
            # With how we operate, as long as it is a directory, we do not
            # care about the "already exists" error.
            pass
        else:
            raise


def create_link(src_path, link_path):
    '''
    Description:
        Create the specified link with some error checking.

    Parameters:
        src_path - The location where the link will point.
        link_path - The location where the link will reside.
    '''

    # Create/Make sure the directory exists
    try:
        os.symlink(src_path, link_path)
    except OSError as ose:
        if (ose.errno == errno.EEXIST and os.path.islink(link_path) and
                src_path == os.path.realpath(link_path)):
            pass
        else:
            raise


def tar_files(tarred_full_path, file_list, gzip=False):
    '''
    Description:
      Create a tar ball (*.tar) of the specified file(s).
      OR
      Create a tar.gz ball (*.tar.gz) of the specified file(s).
    '''

    flags = '-cf'
    target = '%s.tar' % tarred_full_path

    # If zipping was chosen, change the flags and the target name
    if gzip:
        flags = '-czf'
        target = '%s.tar.gz' % tarred_full_path

    cmd = ['tar', flags, target]
    cmd.extend(file_list)
    cmd = ' '.join(cmd)

    output = ''
    try:
        output = execute_cmd(cmd)
    except Exception:
        msg = "Error encountered tar'ing file(s): Stdout/Stderr:"
        if len(output) > 0:
            msg = ' '.join([msg, output])
        else:
            msg = ' '.join([msg, "NO STDOUT/STDERR"])
        # Raise and retain the callstack
        raise Exception(msg)

    return target


def gzip_files(file_list):
    '''
    Description:
      Create a gzip for each of the specified file(s).
    '''

    # Force the gzip file to overwrite any previously existing attempt
    cmd = ['gzip', '--force']
    cmd.extend(file_list)
    cmd = ' '.join(cmd)

    output = ''
    try:
        output = execute_cmd(cmd)
    except Exception:
        msg = "Error encountered compressing file(s): Stdout/Stderr:"
        if len(output) > 0:
            msg = ' '.join([msg, output])
        else:
            msg = ' '.join([msg, "NO STDOUT/STDERR"])
        # Raise and retain the callstack
        raise Exception(msg)
