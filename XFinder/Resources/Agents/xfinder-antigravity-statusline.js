ObjC.import('Foundation');

function run(args) {
    const reader = $.NSFileHandle.fileHandleWithStandardInput;
    const payload = reader.readDataOfLength(262145);
    if (payload.length > 262144) return;
    const decoded = ObjC.unwrap($.NSString.alloc.initWithDataEncoding(payload, $.NSUTF8StringEncoding));
    const status = JSON.parse(decoded);
    if (status.product !== 'antigravity' || !status.quota) return;

    const quota = {};
    for (const [id, bucket] of Object.entries(status.quota).slice(0, 32)) {
        if (!/^[A-Za-z0-9._-]{1,100}$/.test(id) || !bucket || bucket.disabled) continue;
        const fraction = bucket.remaining_fraction;
        const reset = Date.parse(bucket.reset_time);
        if (typeof fraction === 'number' && fraction >= 0 && fraction <= 1 && Number.isFinite(reset)) {
            quota[id] = {remaining_fraction: fraction, reset_time: new Date(reset).toISOString()};
        }
    }
    if (!Object.keys(quota).length) return;

    const directory = args[0] || ObjC.unwrap($.NSHomeDirectory()) + '/Library/Application Support/XFinder/AI Usage';
    const manager = $.NSFileManager.defaultManager;
    const attributes = $.NSDictionary.dictionaryWithObjectForKey($.NSNumber.numberWithInt(448), $.NSFilePosixPermissions);
    if (!manager.createDirectoryAtPathWithIntermediateDirectoriesAttributesError(directory, true, attributes, null)) return;
    const output = $(JSON.stringify({quota: quota})).dataUsingEncoding($.NSUTF8StringEncoding);
    output.writeToFileAtomically(directory + '/antigravity-quota.json', true);
}
