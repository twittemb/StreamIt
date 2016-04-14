
class _QueueItem<T> {
    let value: T!
    var next: _QueueItem?
    
    init(_ newvalue: T?) {
        self.value = newvalue
    }
}


public class Queue<T> {
    
    var _front: _QueueItem<T>
    var _back: _QueueItem<T>
    var maxCapacity: Int
    var currentSize = 0
    
    public init (maxCapacity: Int) {
        // Insert dummy item. Will disappear when the first item is added.
        _back = _QueueItem(nil)
        _front = _back
        self.maxCapacity = maxCapacity
    }
    
    /// Add a new item to the back of the queue.
    public func enqueue (value: T) {
        if (self.currentSize>=maxCapacity){
            _back = _QueueItem(value)
        }else{
            _back.next = _QueueItem(value)
            _back = _back.next!
            self.currentSize += 1
        }

    }
    
    /// Return and remove the item at the front of the queue.
    public func dequeue () -> T? {
        if let newhead = _front.next {
            _front = newhead
            self.currentSize -= 1
            return newhead.value
        } else {
            self.currentSize = 0
            return nil
        }
    }
    
    public func isEmpty() -> Bool {
        return _front === _back
    }
}