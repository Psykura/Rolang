// Standard library: generic singly linked list LinkedList<T>
//
// Nodes are ordinary heap-allocated Rolang structs managed by ARC. Setting
// `head` to nil releases the chain when no other references remain.

pub struct LinkedListNode<T> {
    var next: LinkedListNode<T>?;
    var value: T;
}

pub struct LinkedList<T> {
    var head: LinkedListNode<T>?;
    var count: i32;

    pub static def new() -> LinkedList<T> {
        var result: LinkedList<T>;
        result.head = nil;
        result.count = 0;
        return result;
    }

    pub def len() -> i32 {
        return self.count;
    }

    pub def is_empty() -> Bool {
        return self.count == 0;
    }

    pub def push_front(value: T) -> Void {
        let node: LinkedListNode<T> = LinkedListNode { next: self.head, value: value };
        self.head = node;
        self.count = self.count + 1;
    }

    pub def push_back(value: T) -> Void {
        let node: LinkedListNode<T> = LinkedListNode { next: nil, value: value };

        if let head = self.head {
            var cursor = head;
            while true {
                if let next = cursor.next {
                    cursor = next;
                } else {
                    cursor.next = node;
                    self.count = self.count + 1;
                    return;
                }
            }
        }

        self.head = node;
        self.count = self.count + 1;
    }

    pub def pop_front() -> T? {
        if let head = self.head {
            self.head = head.next;
            self.count = self.count - 1;
            return head.value;
        }

        return nil;
    }

    pub def front() -> T? {
        if let head = self.head {
            return head.value;
        }

        return nil;
    }

    pub def clear() -> Void {
        self.head = nil;
        self.count = 0;
    }
}

pub def linked_list_new<T>() -> LinkedList<T> {
    return LinkedList<T>.new();
}
