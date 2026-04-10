use brotli::enc::writer::CompressorWriter;
use brotli::Decompressor;
use rustler::{Binary, Env, NewBinary, NifResult, ResourceArc, Term};
use std::io::{Read, Write};
use std::sync::Mutex;

/// Shared buffer that CompressorWriter writes into.
/// We drain it after each flush to return compressed bytes to Elixir.
#[derive(Default)]
struct SharedBuf {
    data: Vec<u8>,
}

impl Write for SharedBuf {
    fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
        self.data.extend_from_slice(buf);
        Ok(buf.len())
    }

    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}

/// The encoder state held across NIF calls.
/// Option<> so we can take() it on close to finalize.
struct BrotliEncoder {
    inner: Mutex<Option<CompressorWriter<SharedBuf>>>,
}

#[rustler::resource_impl]
impl rustler::Resource for BrotliEncoder {}

fn on_load(env: Env, _info: Term) -> bool {
    let _ = env;
    true
}

/// Create a new stateful brotli encoder.
/// quality: 0-11, buffer_size is fixed at 4096.
#[rustler::nif(name = "nif_new")]
fn nif_new(quality: u32) -> NifResult<(rustler::types::atom::Atom, ResourceArc<BrotliEncoder>)> {
    let quality = quality.min(11);
    let buf = SharedBuf::default();
    let writer = CompressorWriter::new(buf, 4096, quality, 22);

    let resource = ResourceArc::new(BrotliEncoder {
        inner: Mutex::new(Some(writer)),
    });

    Ok((rustler::types::atom::ok(), resource))
}

/// Feed data into the encoder, flush, and return compressed bytes.
#[rustler::nif(name = "nif_encode")]
fn encode<'a>(
    env: Env<'a>,
    resource: ResourceArc<BrotliEncoder>,
    data: Binary<'a>,
) -> NifResult<(rustler::types::atom::Atom, Binary<'a>)> {
    let mut guard = resource
        .inner
        .lock()
        .map_err(|_| rustler::Error::Term(Box::new("lock poisoned")))?;

    let writer = guard
        .as_mut()
        .ok_or_else(|| rustler::Error::Term(Box::new("encoder already closed")))?;

    // Write input data into the compressor
    writer
        .write_all(data.as_slice())
        .map_err(|e| rustler::Error::Term(Box::new(format!("write error: {e}"))))?;

    // Flush to push compressed bytes to the underlying SharedBuf
    writer
        .flush()
        .map_err(|e| rustler::Error::Term(Box::new(format!("flush error: {e}"))))?;

    // Drain the compressed bytes from the shared buffer
    let compressed = writer.get_mut().data.split_off(0);

    let mut out = NewBinary::new(env, compressed.len());
    out.as_mut_slice().copy_from_slice(&compressed);

    Ok((rustler::types::atom::ok(), out.into()))
}

/// Finalize the encoder, returning any remaining compressed bytes.
/// The encoder cannot be used after this call.
#[rustler::nif(name = "close")]
fn close<'a>(
    env: Env<'a>,
    resource: ResourceArc<BrotliEncoder>,
) -> NifResult<(rustler::types::atom::Atom, Binary<'a>)> {
    let mut guard = resource
        .inner
        .lock()
        .map_err(|_| rustler::Error::Term(Box::new("lock poisoned")))?;

    let writer = guard
        .take()
        .ok_or_else(|| rustler::Error::Term(Box::new("encoder already closed")))?;

    // into_inner() consumes the CompressorWriter, flushing the final brotli frame
    let buf = writer.into_inner();

    let compressed = buf.data;
    let mut out = NewBinary::new(env, compressed.len());
    out.as_mut_slice().copy_from_slice(&compressed);

    Ok((rustler::types::atom::ok(), out.into()))
}

/// One-shot decompression for testing round-trips.
#[rustler::nif(name = "decompress")]
fn decompress<'a>(
    env: Env<'a>,
    data: Binary<'a>,
) -> NifResult<(rustler::types::atom::Atom, Binary<'a>)> {
    let mut decompressor = Decompressor::new(data.as_slice(), 4096);
    let mut decompressed = Vec::new();

    decompressor
        .read_to_end(&mut decompressed)
        .map_err(|e| rustler::Error::Term(Box::new(format!("decompress error: {e}"))))?;

    let mut out = NewBinary::new(env, decompressed.len());
    out.as_mut_slice().copy_from_slice(&decompressed);

    Ok((rustler::types::atom::ok(), out.into()))
}

rustler::init!("Elixir.Brotlex.Native", load = on_load);
