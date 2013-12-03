// Generated by CoffeeScript 1.6.3
(function() {
  $(function() {
    $('#btn-edit').click(function(e) {
      e.preventDefault();
      $(this).hide();
      $('#input-edit').show();
      return $('#edit input:first').focus().select();
    });
    $('#btn-cancel').on('click', function(e) {
      e.preventDefault();
      $('#input-edit').hide();
      return $('#btn-edit').show();
    });
    $('#btn-submit:not(.disabled)').on('click', function(e) {
      var $this;
      $this = $(this);
      $this.addClass('disabled');
      e.preventDefault();
      return $.ajax(location.href, {
        type: 'PUT',
        data: $('#edit').serialize(),
        dataType: 'json',
        success: function(data, textStatus, jqXHR) {
          return location.reload();
        },
        error: function(jqXHR, textStatus, errorThrown) {
          return alert('error', jqXHR.responseJSON.error);
        },
        complete: function(jqXHR, textStatus) {
          return $this.removeClass('disabled');
        }
      });
    });
    return $('body').keypress(function(e) {
      var ESC, key;
      ESC = 27;
      key = e.charCode || e.keyCode || 0;
      if (key !== ESC) {
        return;
      }
      return $('#btn-cancel').trigger('click');
    });
  });

}).call(this);