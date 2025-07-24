//=============================================================//
//                                                             //
//                         STREAMS                             //
//                                                             //
//   The stdout, stderr and stdin streams must only be         //
//  intitialized once, preferably in the main function.        //
//                                                             //
//=============================================================//

const std = @import("std");

pub var global_streams: Streams = undefined;

pub const Streams = struct {
    stdout: std.io.GenericWriter(
        std.fs.File,
        error{
            NoSpaceLeft,
            DiskQuota,
            FileTooBig,
            InputOutput,
            DeviceBusy,
            InvalidArgument,
            AccessDenied,
            BrokenPipe,
            SystemResources,
            OperationAborted,
            NotOpenForWriting,
            LockViolation,
            WouldBlock,
            ConnectionResetByPeer,
            ProcessNotFound,
            NoDevice,
            Unexpected,
        },
        std.fs.File.write,
    ),
    stderr: std.io.GenericWriter(
        std.fs.File,
        error{
            NoSpaceLeft,
            DiskQuota,
            FileTooBig,
            InputOutput,
            DeviceBusy,
            InvalidArgument,
            AccessDenied,
            BrokenPipe,
            SystemResources,
            OperationAborted,
            NotOpenForWriting,
            LockViolation,
            WouldBlock,
            ConnectionResetByPeer,
            ProcessNotFound,
            NoDevice,
            Unexpected,
        },
        std.fs.File.write,
    ),
    stdin: std.io.GenericReader(
        std.fs.File,
        error{
            InputOutput,
            AccessDenied,
            BrokenPipe,
            SystemResources,
            OperationAborted,
            LockViolation,
            WouldBlock,
            ConnectionResetByPeer,
            ProcessNotFound,
            Unexpected,
            IsDir,
            ConnectionTimedOut,
            NotOpenForReading,
            SocketNotConnected,
            Canceled,
        },
        std.fs.File.read,
    ),

    pub fn init() Streams {
        return Streams{
            .stdout = std.io.getStdOut().writer(),
            .stderr = std.io.getStdErr().writer(),
            .stdin = std.io.getStdIn().reader(),
        };
    }
};
